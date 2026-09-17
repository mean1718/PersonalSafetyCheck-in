const User = require("../models/User");

// firebaseAdmin.js throws at require-time if serviceAccountKey.json is
// missing (a real Firebase service account, downloaded from the Firebase
// console — not something that can be faked). Every other push-triggering
// controller only wants "best effort, never blocks the real feature", so
// that require happens once, here, guarded — if it fails, push just quietly
// no-ops everywhere instead of crashing the whole API.
let messaging = null;
try {
  messaging = require("../firebaseAdmin");
} catch (error) {
  console.warn(
    "Push notifications disabled: " +
      error.message +
      " (see backend_SafetyU/src/firebaseAdmin.js — needs serviceAccountKey.json from the Firebase console).",
  );
}

/// Sends a real device push to every token this user has registered (they
/// can have more than one — phone + tablet, or a reinstall that got a new
/// token before the old one expired). Invalid/expired tokens returned by
/// Firebase are pruned from the user's record so they stop being retried
/// forever. Never throws — a push failure should never take down the
/// safety-alert / trust-request flow that triggered it.
const ANDROID_CHANNEL_BY_TYPE = {
  trust_request: "trust_requests",
  safety_alert: "safety_alerts",
  checkin_completed: "safety_resolved",
};

async function sendPushToUser(userId, { title, body, data = {} }) {
  if (!messaging || !userId) return;
  try {
    const user = await User.findById(userId).select("fcmTokens");
    const tokens = (user?.fcmTokens || []).filter(Boolean);
    if (!tokens.length) return;

    const channelId = ANDROID_CHANNEL_BY_TYPE[data.type] || "safety_alerts";

    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)]),
      ),
      android: {
        priority: "high",
        notification: {
          channelId,
          priority: "max",
          sound: "default",
        },
      },
      apns: { payload: { aps: { sound: "default" } } },
    });

    const deadTokens = [];
    response.responses.forEach((r, i) => {
      if (
        !r.success &&
        [
          "messaging/registration-token-not-registered",
          "messaging/invalid-registration-token",
        ].includes(r.error?.code)
      ) {
        deadTokens.push(tokens[i]);
      }
    });
    if (deadTokens.length) {
      await User.updateOne(
        { _id: userId },
        { $pull: { fcmTokens: { $in: deadTokens } } },
      );
    }
  } catch (error) {
    console.warn(
      `Push notification skipped for user ${userId}: ${error.message}`,
    );
  }
}

/// Convenience for the many places that already build a list of receiver
/// ids (insertMany over selected/trusted contacts) — fires one push per
/// recipient without making the caller loop and await each one inline.
async function sendPushToUsers(userIds, payload) {
  await Promise.all(
    [...new Set(userIds.map((id) => id?.toString()).filter(Boolean))].map(
      (id) => sendPushToUser(id, payload),
    ),
  );
}

module.exports = { sendPushToUser, sendPushToUsers };
