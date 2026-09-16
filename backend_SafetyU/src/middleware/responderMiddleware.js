const requireResponder = (req, res, next) => {
  if (req.user?.role !== "responder") {
    return res.status(403).json({
      message: "Responder access required.",
    });
  }

  if (req.user?.responderStatus !== "approved") {
    return res.status(403).json({
      message: "Responder account is not approved yet.",
    });
  }

  next();
};

module.exports = requireResponder;