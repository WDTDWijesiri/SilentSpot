const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

exports.sendInboxPush = onDocumentCreated(
  {
    document: "users/{userId}/notifications/{notificationId}",
    region: "asia-south1"
  },
  async (event) => {
    const notification = event.data?.data();
    if (!notification) return;

    const userReference = getFirestore().collection("users").doc(event.params.userId);
    const user = await userReference.get();
    const tokens = [...new Set(user.get("fcmTokens") || [])];
    if (tokens.length === 0) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: notification.title || "SilentSpot",
        body: notification.message || "You have a new SilentSpot update."
      },
      data: {
        notificationId: event.params.notificationId,
        symbol: notification.symbol || "bell.fill"
      },
      apns: {
        payload: {
          aps: {
            sound: "default"
          }
        }
      }
    });

    const invalidTokens = [];
    response.responses.forEach((result, index) => {
      if (!result.success && [
        "messaging/invalid-registration-token",
        "messaging/registration-token-not-registered"
      ].includes(result.error?.code)) {
        invalidTokens.push(tokens[index]);
      }
    });

    if (invalidTokens.length > 0) {
      await userReference.update({
        fcmTokens: FieldValue.arrayRemove(...invalidTokens)
      });
    }
  }
);
