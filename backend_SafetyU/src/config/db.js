const mongoose = require("mongoose");

const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI);
    console.log("MongoDB connected successfully");

    try {
      const User = require("../models/User");
      const indexes = await User.collection.indexes();
      const stale = indexes.find(
        (i) => i.name === "officerId_1" && !i.partialFilterExpression,
      );
      if (stale) {
        await User.collection.dropIndex("officerId_1");
        console.log("Dropped stale officerId_1 index");
      }
      await User.createIndexes();
    } catch (e) {
      console.error("User index migration failed:", e.message);
    }
  } catch (error) {
    console.error("MongoDB connection failed:", error.message);
    process.exit(1);
  }
};

module.exports = connectDB;
