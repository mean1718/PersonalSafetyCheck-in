// src/services/bakongClient.js
const {
  checkTransactionStatusByMD5,
  generatePaymentQR,
} = require("../utils/khqr");

module.exports = {
  checkTransactionByMd5: checkTransactionStatusByMD5,
  generateQr: generatePaymentQR,
};
