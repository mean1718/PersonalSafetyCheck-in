const CheckIn = require("../models/CheckIn");
const User = require("../models/User");
const Notification = require("../models/Notification");
const { sendPushToUsers } = require("./pushService");

// The phone's own countdown is what normally alerts trusted contacts when
// someone doesn't check in. But a phone that died, lost signal, was
// switched off, or had SafetyU suspended by the OS can't run that timer --
// exactly the situations where the person is most likely to need help.
// This runs on the SERVER and alerts the selected contacts if a session is
// still active well past its deadline and nobody has been alerted yet.

const CHECK_EVERY_MS = 30 * 1000;
// Give the phone's own escalation a head start so contacts aren't alerted
// twice for the same missed deadline.
const GRACE_MS = 90 * 1000;

let running = false;

async function checkOverdueSessions() {
  if (running) return;
  running = true;
  try {
    const cutoff = new Date(Date.now() - GRACE_MS);
    const overdue = await CheckIn.find({
      status: "active",
      expectedEndAt: { $lte: cutoff },
      deadlineAlertedAt: null,
      "trustedContactUsers.0": { $exists: true },
    })
      .select("_id")
      .limit(50);

    for (const { _id } of overdue) {
      // Claim it atomically so two server instances (or a phone that
      // escalates at the same moment) can't both alert.
      const checkIn = await CheckIn.findOneAndUpdate(
        { _id, status: "active", deadlineAlertedAt: null },
        { $set: { deadlineAlertedAt: new Date() } },
        { new: true },
      );
      if (!checkIn) continue;

      const owner = await User.findById(checkIn.user).select("name");
      const ownerName = owner?.name || "A trusted contact";
      const place = checkIn.destinationName
        ? ` on the way to ${checkIn.destinationName}`
        : "";
      const message = `${ownerName} hasn't checked in${place} and may need help.`;
      const receivers = (checkIn.trustedContactUsers || []).map(String);

      await Notification.insertMany(
        receivers.map((receiver) => ({
          receiver,
          sender: checkIn.user,
          checkIn: checkIn._id,
          type: "safety_alert",
          title: "SafetyU Alert",
          message,
          ...(checkIn.location?.latitude != null &&
          checkIn.location?.longitude != null
            ? {
                location: {
                  latitude: checkIn.location.latitude,
                  longitude: checkIn.location.longitude,
                },
              }
            : {}),
        })),
      );
      await sendPushToUsers(receivers, {
        title: "SafetyU Alert",
        body: message,
        data: {
          type: "safety_alert",
          checkInId: checkIn._id.toString(),
          ownerName,
        },
      });
      console.log(
        `[deadlineWatcher] alerted ${receivers.length} contact(s) for overdue session ${checkIn._id}`,
      );
    }
  } catch (error) {
    console.error("[deadlineWatcher] failed:", error.message);
  } finally {
    running = false;
  }
}

function startDeadlineWatcher() {
  setInterval(checkOverdueSessions, CHECK_EVERY_MS);
  console.log("Deadline watcher started.");
}

module.exports = { startDeadlineWatcher, checkOverdueSessions };
