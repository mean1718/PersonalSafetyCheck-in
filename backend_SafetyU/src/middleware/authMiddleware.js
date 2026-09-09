const jwt = require("jsonwebtoken");
const User = require("../models/User");

const protect = async (req, res, next) => {
    try {
        const authHeader = req.headers.authorization;

        if (!authHeader || !/^Bearer\s+\S+$/.test(authHeader)) {
            return res.status(401).json({
                message: "Authentication token is required."
            });
        }

        if (!process.env.JWT_SECRET) {
            console.error("JWT_SECRET is not configured");
            return res.status(500).json({ message: "Server authentication is not configured." });
        }

        const token = authHeader.replace(/^Bearer\s+/, "");

        const decoded = jwt.verify(token, process.env.JWT_SECRET);

        const user = await User.findById(decoded.id).select("_id name email phone role createdAt");
        if (!user) {
            return res.status(401).json({ message: "Invalid or expired token." });
        }

        req.user = {
            id: user._id.toString(),
            role: user.role,
        };
        req.authenticatedUser = user;

        next();

    } catch (error) {
        return res.status(401).json({
            message: "Invalid or expired token."
        });
    }
};

module.exports = protect;
