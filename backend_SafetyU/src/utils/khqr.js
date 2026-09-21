// src/utils/khqr.js
const axios = require("axios");
const { BakongKHQR, khqrData, IndividualInfo } = require("bakong-khqr");

const stripTrailingV1 = (url) =>
  (url || "").replace(/\/+$/, "").replace(/\/v1$/, "");

const BAKONG_API_URL =
  stripTrailingV1(process.env.BAKONG_API_URL) ||
  stripTrailingV1(
    process.env.NODE_ENV === "production"
      ? process.env.BAKONG_PROD_BASE_API_URL
      : process.env.BAKONG_DEV_BASE_API_URL,
  ) ||
  "https://api-bakong.nbc.gov.kh";

const generatePaymentQR = ({
  bakongAccountId,
  merchantName,
  merchantCity = "Phnom Penh",
  amount,
  currency = "KHR",
  billNumber,
  storeLabel,
}) => {
  try {
    const accountId =
      bakongAccountId ||
      process.env.BAKONG_ACCOUNT_ID ||
      process.env.BAKONG_ACCOUNT_USERNAME;

    if (!accountId) {
      throw new Error("Bakong account ID is missing.");
    }

    const finalMerchantName =
      merchantName ||
      process.env.MERCHANT_NAME ||
      process.env.BAKONG_ACCOUNT_NAME ||
      "SafetyU";

    const numericAmount = Number(amount);
    if (!Number.isFinite(numericAmount) || numericAmount <= 0) {
      throw new Error(`Invalid payment amount: ${amount}`);
    }

    const finalCurrency = String(currency).toUpperCase();
    const selectedCurrency =
      finalCurrency === "USD" ? khqrData.currency.usd : khqrData.currency.khr;

    const safeBillNumber = billNumber
      ? String(billNumber).substring(0, 25)
      : `SU-${Date.now()}`.substring(0, 25);

    // Minimal optional data payload (omitting storeLabel, terminalLabel, etc.)
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000);
    const optionalData = {
      currency: selectedCurrency,
      amount: numericAmount,
      billNumber: safeBillNumber,
      expirationTimestamp: expiresAt.getTime(),
      // Only sent when paymentController needs to force a different QR
      // (and therefore a different md5) after a collision.
      ...(storeLabel
        ? { storeLabel: String(storeLabel).substring(0, 25) }
        : {}),
    };

    console.log("========== MINIMAL KHQR GENERATION ==========");
    console.log("Account ID:", accountId);
    console.log("Merchant:", finalMerchantName);
    console.log("Amount:", numericAmount);
    console.log("Currency:", finalCurrency);
    console.log("=============================================");

    const individualInfo = new IndividualInfo(
      accountId,
      finalMerchantName,
      merchantCity || "Phnom Penh",
      optionalData,
    );

    const khqr = new BakongKHQR();
    const response = khqr.generateIndividual(individualInfo);

    if (!response || (response.status && response.status.code !== 0)) {
      throw new Error(
        response?.status?.message || "Failed to generate minimal KHQR.",
      );
    }

    if (!response.data?.qr) {
      throw new Error("KHQR generator did not return a QR string.");
    }

    return {
      qrString: response.data.qr,
      qr: response.data.qr,
      md5: response.data.md5,
      expiresAt,
    };
  } catch (error) {
    console.error("KHQR Generation Error:", error);
    throw new Error(`KHQR Generation Error: ${error.message}`);
  }
};

const checkTransactionStatusByMD5 = async (md5Hash) => {
  try {
    const token = process.env.BAKONG_ACCESS_TOKEN;
    if (!token) throw new Error("Bakong access token is missing.");

    const response = await axios.post(
      `${BAKONG_API_URL}/v1/check_transaction_by_md5`,
      { md5: md5Hash },
      {
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        timeout: 15000,
      },
    );

    const data = response.data;
    const paid = data?.responseCode === 0 && !!data?.data;
    return { paid, raw: data };
  } catch (error) {
    const errorMsg = error.response?.data?.responseMessage || error.message;
    if (
      error.response?.status === 401 ||
      errorMsg.toLowerCase().includes("token")
    ) {
      throw new Error("Bakong access token is invalid or expired.");
    }
    throw new Error(`getPaymentStatus error: ${errorMsg}`);
  }
};

module.exports = {
  generatePaymentQR,
  generateQr: generatePaymentQR,
  checkTransactionStatusByMD5,
  checkTransactionByMd5: checkTransactionStatusByMD5,
  buildIndividualKHQR: generatePaymentQR,
};
