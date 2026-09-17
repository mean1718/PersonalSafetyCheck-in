const path = require("path");
const fs = require("fs");

const { cert, getApps, initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");

// Firebase service account key
const serviceAccountPath = path.join(__dirname, "..", "serviceAccountKey.json");

// Check that the key exists
if (!fs.existsSync(serviceAccountPath)) {
  throw new Error(
    `Firebase serviceAccountKey.json not found at: ${serviceAccountPath}`,
  );
}

try {
  const serviceAccount = require(serviceAccountPath);

  // Prevent Firebase from being initialized multiple times
  const firebaseApp =
    getApps().length === 0
      ? initializeApp({
          credential: cert(serviceAccount),
        })
      : getApps()[0];

  console.log("✅ Firebase Admin initialized successfully");

  // Firebase Cloud Messaging
  const messaging = getMessaging(firebaseApp);

  module.exports = messaging;
} catch (error) {
  console.error("❌ Firebase Admin initialization failed:");
  console.error(error.message);

  throw error;
}
