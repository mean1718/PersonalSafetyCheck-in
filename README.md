# SafetyU - Personal Safety Check-In Platform

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?logo=node.js&logoColor=white)
![Express](https://img.shields.io/badge/Express-000000?logo=express&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-47A248?logo=mongodb&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?logo=firebase&logoColor=black)
![Status](https://img.shields.io/badge/status-prototype-orange)

SafetyU is a personal safety app that helps keep you connected when you're on the move. Start a safety check-in before a risky trip, set a deadline, and choose trusted contacts to watch over you. If you miss your check-in or activate SOS, your trusted contacts are alerted and can see your live location.

[🚀 Live Demo](https://safetyu.vercel.app) • [🔌 API Health](https://personalsafetycheck-in.onrender.com/api/health) • [🐛 Report Bug](https://github.com/mean1718/PersonalSafetyCheck-in/issues) • [✨ Request Feature](https://github.com/mean1718/PersonalSafetyCheck-in/issues)

> ## ⚠️ Prototype Notice
> SafetyU is a **still prototype**. It is **not connected to real emergency services** (police, ambulance or fire) and must **not** be relied on in a real emergency. In a real emergency, call your local emergency number directly.
>
> The prototype alerts a person's **trusted contacts** and notifies **responder accounts** registered inside the app (verified with sample Officer IDs). Connecting to real emergency services is planned future work.

## 📋 Table of Contents

- [✨ Features](#-features)
- [🏗️ Architecture](#️-architecture)
- [🚀 Quick Start](#-quick-start)
- [📁 Project Structure](#-project-structure)
- [🛠️ Technology Stack](#️-technology-stack)
- [📚 API Documentation](#-api-documentation)
- [🚨 Emergency Features (Prototype)](#-emergency-features-prototype)
- [💳 Plans and Payments](#-plans-and-payments)
- [🔧 Configuration](#-configuration)
- [🧪 Testing](#-testing)
- [📈 Deployment](#-deployment)
- [🔒 Security](#-security)
- [🩺 Troubleshooting](#-troubleshooting)
- [🗺️ Roadmap](#️-roadmap)
- [🤝 Contributing](#-contributing)
- [📞 Support](#-support)
- [📄 License](#-license)
- [🙏 Acknowledgments](#-acknowledgments)

## ✨ Features

### 🎯 Core Functionality
- 🛡️ **Safety Check-In Sessions** - Set a destination and deadline, and choose who to notify
- ⏰ **Missed Check-In Alerts** - Contacts are alerted automatically if you don't check in
- 🖥️ **Server-Side Backup** - A background job alerts contacts even if your phone died or lost signal
- 📍 **Live Location Sharing** - Trusted contacts see your location on a map with directions
- 🔐 **User Authentication** - Secure login and signup with JWT tokens
- 🔑 **Emergency PIN** - A 4-digit PIN confirms an alert is intentional

### 👥 Trust Network
- 🤝 **Trusted Contacts** - Send and accept trust requests
- 🥇 **Primary and Secondary Contacts** - Alerts escalate from primary to secondary
- ✅ **Contact Replies** - Contacts answer *Can help*, *Cannot help* or *Marked safe*
- 💬 **In-App Chat** - Talk with the person who sent the alert

### 🚨 Emergency and Responders (Prototype)
- 🆘 **SOS / Emergency Assistant** - Escalates through three levels
- 👮 **Responder Accounts** - Verified with an assigned Officer ID
- 📋 **Case Management** - Accept, update and resolve emergency cases
- 🟢 **Online Status** - Responders show as online or offline

### 💳 Payments and Plans
- 💵 **Bakong KHQR Payments** - Pay in USD or KHR
- 🎟️ **Free, Extra Slots and Pro** - Plan-based limits on trusted contacts
- 🧾 **Payment History** - Track every purchase

### 🎨 Experience
- 📱 **Cross-Platform** - One Flutter codebase for Android, iOS and Web
- 🔔 **Notifications** - In-app alerts plus push notifications on mobile
- 🕘 **Session History** - Review past check-ins
- 🌙 **Light and Dark Theme**

## 🏗️ Architecture

SafetyU follows a client-server architecture:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Flutter App    │    │   Express API   │    │    MongoDB      │
│  (Dart)         │◄──►│   (Node.js)     │◄──►│    Database     │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                       ▲                       ▲
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│    Firebase     │    │   Bakong API    │    │  Google Maps    │
│ (Push Alerts)   │    │ (KHQR Payments) │    │  (Directions)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### How a Session Works

```
Start session ──▶ Share location ──▶ User taps "I'm safe" ──▶ Session completed
 (deadline,          (live map)              │
  contacts)                                  └── or deadline passes ──▶ Alert sent to contacts
```

A background job on the server runs **every 30 seconds**. If a session is still active more than **90 seconds** past its deadline and nobody was alerted, it alerts the selected contacts itself. Each session is claimed atomically, so contacts are never alerted twice.

## 🚀 Quick Start

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable)
- [Node.js](https://nodejs.org/) (v18 or higher)
- [MongoDB](https://www.mongodb.com/) (local or MongoDB Atlas)
- npm
- Optional: Firebase project (push), Google Maps API key, Bakong merchant account (payments)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/mean1718/PersonalSafetyCheck-in.git
   cd PersonalSafetyCheck-in
   ```

2. **Install dependencies**
   ```bash
   # Backend
   cd backend_SafetyU
   npm install

   # Frontend
   cd ../Frontend_SafetyU/safetyU_app
   flutter pub get
   ```

3. **Environment setup**

   Create `backend_SafetyU/src/config/.env`:
   ```env
   NODE_ENV=development
   PORT=5000
   MONGODB_URI=mongodb://localhost:27017/safetyu
   JWT_SECRET=your-secret-key
   GOOGLE_MAPS_API_KEY=your-google-maps-key

   # Bakong KHQR payments (optional)
   BAKONG_ACCOUNT_USERNAME=your-account
   BAKONG_ACCOUNT_NAME=your-name
   BAKONG_MERCHANT_CITY=Phnom Penh
   BAKONG_ACCESS_TOKEN=your-token
   ```

   Set the API address in `Frontend_SafetyU/safetyU_app/lib/services/api_config.dart`:
   ```dart
   class ApiConfig {
     static const String baseUrl = 'http://localhost:5000/api';
     // Android emulator: 'http://10.0.2.2:5000/api'
     // Live server:      'https://personalsafetycheck-in.onrender.com/api'
   }
   ```

4. **Optional: seed sample responder data**
   ```bash
   cd backend_SafetyU
   node src/scripts/seedResponderData.js
   ```

5. **Start the servers**
   ```bash
   # Terminal 1 - Backend
   cd backend_SafetyU
   node src/server.js

   # Terminal 2 - Frontend
   cd Frontend_SafetyU/safetyU_app
   flutter run -d chrome
   ```

6. **Access the application**
   - Frontend: the URL Flutter prints (for example `http://localhost:60996`)
   - Backend API: `http://localhost:5000/api`
   - Health check: `http://localhost:5000/api/health`

## 📁 Project Structure

```
PersonalSafetyCheck-in/
├── 📁 Frontend_SafetyU/
│   └── 📁 safetyU_app/              # Flutter app
│       ├── 📁 android/ ios/ linux/  # Platform folders
│       ├── 📁 assets/images/        # Images
│       ├── 📁 lib/
│       │   ├── 📁 screens/          # UI screens (login, home, session, SOS, cases...)
│       │   ├── 📁 services/         # API client, auth, payments, location, push
│       │   ├── 📁 models/           # Data models
│       │   ├── 📁 widgets/          # Reusable widgets
│       │   ├── 📁 theme/            # Colors and theme controller
│       │   ├── 📁 utils/            # Validators
│       │   ├── 📄 firebase_options.dart
│       │   └── 📄 main.dart         # Entry point and routes
│       └── 📄 pubspec.yaml
│
├── 📁 backend_SafetyU/              # Express backend
│   ├── 📁 src/
│   │   ├── 📁 config/               # Database connection and .env
│   │   ├── 📁 controllers/          # Request handlers
│   │   ├── 📁 middleware/           # Auth and responder guards
│   │   ├── 📁 models/               # Mongoose schemas
│   │   ├── 📁 routes/               # API route definitions
│   │   ├── 📁 services/             # Deadline watcher, push, Bakong client
│   │   ├── 📁 utils/                # KHQR generation, extra-slot rules
│   │   ├── 📁 scripts/              # Seed data
│   │   ├── 📄 firebaseAdmin.js      # Firebase Admin setup
│   │   └── 📄 server.js             # Server entry point
│   └── 📄 package.json
│
└── 📄 README.md                     # This file
```

## 🛠️ Technology Stack

### Frontend
| Technology | Purpose |
|------------|---------|
| Flutter (Dart) | Cross-platform UI (Android, iOS, Web) |
| Geolocator | Location and permissions |
| Google Maps | Live map and directions |
| Firebase Messaging | Push notifications on mobile |
| HTTP | REST API client |

### Backend
| Technology | Purpose |
|------------|---------|
| Node.js | Runtime environment |
| Express | Web framework |
| MongoDB | Primary database |
| Mongoose | ODM |
| JWT | Authentication |
| bcrypt | Password and PIN hashing |
| Firebase Admin | Sending push notifications |
| Bakong KHQR | Payments |

### Hosting
- **Vercel** - Flutter web app
- **Render** - Express API
- **MongoDB Atlas** - Cloud database

## 📚 API Documentation

Base URL: `/api`. Routes marked 🔒 need the header `Authorization: Bearer <token>`. Errors are JSON: `{ "message": "..." }`.

### Key Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| POST | `/api/users/register` | User or responder registration |
| POST | `/api/users/login` | User authentication |
| POST | `/api/users/verify-emergency-pin` 🔒 | Check the Emergency PIN |
| POST | `/api/checkins` 🔒 | Start a safety session |
| PUT | `/api/checkins/:id/complete` 🔒 | Complete a session |
| PUT | `/api/checkins/:id/extend` 🔒 | Extend the deadline |
| POST | `/api/checkins/:id/need-help` 🔒 | Ask contacts for help now |
| POST | `/api/trust-requests` 🔒 | Send a trust request |
| POST | `/api/emergency` 🔒 | Create an emergency |
| GET | `/api/emergency/responder/cases` 🔒 | Responder case list |
| POST | `/api/payments/khqr` 🔒 | Create a KHQR payment |
| GET | `/api/payments/pricing` | Current prices |

<details>
<summary><b>All routes</b></summary>

**Users** `/api/users`: `/register`, `/login`, `/logout` 🔒, `/verify-emergency-pin` 🔒, `/create-emergency-pin` 🔒, `/change-emergency-pin` 🔒, `/device-token` 🔒, `/device-token/remove` 🔒, `/profile` 🔒

**Check-ins** `/api/checkins` 🔒: `POST /`, `GET /`, `GET /trusted-contacts`, `PUT /:id/complete`, `POST /complete-all-active`, `PUT /:id/extend`, `PUT|GET /:id/location`, `POST /:id/need-help`, `POST /:id/confirm-safe`, `GET /:id/alert-status`

**Trusted contacts** `/api/trusted-contacts`: create, list, update, delete (limited by plan)

**Trust requests** `/api/trust-requests`: `POST /`, `GET /received`, `POST /:id/accept`, `POST /:id/reject`, `POST /remove-by-phone`

**Emergency** `/api/emergency`: `POST /`, `GET /`, `POST /:id/secondary`, `POST /:id/emergency`, `GET /responder/cases`, `PUT /:id/accept`, `PUT /:id/resolve`

**Location** `/api/location`: `POST /`, `POST /stop`, `GET /contacts`

**Chat** `/api/chat`: `POST /`, `GET /unread/counts`, `GET /:userId`

**Notifications** `/api/notifications`: `GET /`, `GET /alerts`, `PUT /:id/read`, `PUT /:id/response`, `DELETE /`

**Directions** `/api/directions`: `GET /`

**Payments** `/api/payments`: `GET /pricing`, `POST /khqr`, `GET /khqr/:md5/status`, `GET /history`

</details>

## 🚨 Emergency Features (Prototype)

The emergency flow demonstrates the idea end to end. **No real emergency service is contacted.**

### Escalation Levels
```
Level 1: primary contacts ──▶ Level 2: secondary contacts ──▶ Level 3: responder accounts
```

1. The user opens the Emergency Assistant and confirms with the **Emergency PIN**, so an alert cannot be sent by accident.
2. An emergency case is created with the user's location.
3. Primary contacts are alerted first, then secondary contacts if nobody responds.
4. The case then appears for **responder accounts** inside SafetyU, who can accept it, chat with the user, update it and mark it resolved.

### ✅ What Works
- PIN-protected SOS
- Three-level escalation and contact replies
- Responder case list, accept and resolve
- Live location on the map

### 🚧 Simulated or Not Built Yet
- Responder accounts use **sample Officer IDs** and are not real police, ambulance or fire officers
- No call or message is sent to any real emergency service
- Police stations in the database are test data
- Push notifications work on mobile only; on web, alerts show inside the app

### 🎬 Demo Guide
1. Create two user accounts and add each other as trusted contacts.
2. Create a responder account with a sample Officer ID.
3. Trigger the emergency from the first account with its PIN.
4. Watch the alert reach the contact, then the responder.

## 💳 Plans and Payments

| Plan | Trusted Contacts | How to Get It |
|------|------------------|---------------|
| 🆓 **Free** | 2 main + 1 other | Default |
| 🎟️ **Extra Slots** | Free limit + purchased slots | Pay per contact, valid 24 hours |
| ⭐ **Pro** | Unlimited | Monthly subscription (30 days) |

Prices in the current code: **Pro $2.99 / month** and **$0.20 per extra contact**. The app reads live prices from `GET /api/payments/pricing`.

**Payment flow:** the app requests a KHQR code, the user pays in any Bakong-supported banking app, the backend confirms the payment with the Bakong API and checks the amount, then credits the account and sends a confirmation.

## 🔧 Configuration

### Backend Environment Variables

```env
# Server
NODE_ENV=development|production
PORT=5000

# Database (required)
MONGODB_URI=mongodb://localhost:27017/safetyu

# Authentication (required)
JWT_SECRET=your-jwt-secret

# Maps
GOOGLE_MAPS_API_KEY=your-google-maps-key

# Bakong KHQR payments
BAKONG_ACCOUNT_USERNAME=your-account
BAKONG_ACCOUNT_NAME=your-name
BAKONG_MERCHANT_CITY=Phnom Penh
BAKONG_ACCESS_TOKEN=your-token
BAKONG_ACCOUNT_CURRENCY=USD
BAKONG_USD_TO_KHR_RATE=4100
BAKONG_DEV_BASE_API_URL=<sandbox url>
BAKONG_PROD_BASE_API_URL=<live url>
```

Also optional: `backend_SafetyU/serviceAccountKey.json` (Firebase Admin key). Without it the server still runs; only push notifications are disabled.

> **Never commit `.env` or `serviceAccountKey.json`.** Keep them in `.gitignore`. On Render, enter the variables under **Environment**.

### Frontend Configuration

Set `baseUrl` in `lib/services/api_config.dart` (see [Quick Start](#-quick-start)).

## 🧪 Testing

There are no automated tests yet. Use this manual checklist after every deployment:

- [ ] `GET /api/health` returns `{"status":"ok"}`
- [ ] Sign up a new user with a 4-digit Emergency PIN and reach the home dashboard
- [ ] Log out and log in again
- [ ] Add trusted contacts (the Free limit blocks a 3rd main contact)
- [ ] Start a session and complete it with **I'm safe**
- [ ] Let a short session expire and confirm the contact gets an alert
- [ ] Trigger SOS with the right PIN, and check that a wrong PIN is rejected
- [ ] Sign up a responder with a sample Officer ID and open the case list
- [ ] Open a KHQR payment and check its status
- [ ] Open the Vercel site in a private window and repeat sign up

## 📈 Deployment

### Backend on Render
1. Push `backend_SafetyU` to GitHub.
2. Create a **Web Service** on Render from the repo (leave **Root Directory** empty when `package.json` is at the top of the repo).
3. Set the **Start Command** to `node src/server.js` (or `npm start` if defined in `package.json`).
4. Add the environment variables from [Configuration](#-configuration).
5. Deploy and open `/api/health`. It must return `{"status":"ok"}`.

> The Render free tier sleeps after about 15 minutes idle, so the first request can take up to a minute. Ping `/api/health` every 5 minutes with a free monitor such as UptimeRobot, or use a paid instance.

### Web App on Vercel
```bash
cd Frontend_SafetyU/safetyU_app
flutter build web --release
cd build/web
npx vercel --prod
```
- Deploy from **`build/web`**, not the source folder, or the site shows a 404.
- If a `.vercel` folder exists in `safetyU_app`, delete it.
- For Google Maps on web, add your Vercel domain to the key's allowed HTTP referrers.

### Mobile
```bash
flutter build apk --release      # Android
flutter build ios --release      # iOS (needs macOS)
```

## 🔒 Security

- 🔐 Passwords and Emergency PINs are hashed with **bcrypt** and never returned by the API
- 🎫 **JWT** tokens expire after 7 days
- 🛂 Protected routes use auth middleware; responder routes have an extra guard
- 💳 Payments are verified with the Bakong API, including the amount, before crediting
- 🙈 Secrets stay in environment variables and out of Git; rotate any secret that was ever pushed publicly
- 🌐 Restrict CORS to your own domains before wider use

## 🩺 Troubleshooting

| Problem | Cause and Fix |
|---------|---------------|
| "Could not reach the SafetyU server … TimeoutException" | Render was asleep. Wait up to a minute and retry; use an uptime monitor. |
| `Cannot GET /api/health` | Render is running an old build. Check the **Events** tab and redeploy the latest commit. |
| Signup returns 409 "An account with these details already exists" | Caused by a stale `officerId_1` index on older versions. The current `db.js` drops and rebuilds it on startup. |
| Render deploy fails | Check **Logs**. A missing `MONGODB_URI` or `JWT_SECRET` is the usual cause. |
| Vercel shows `404 NOT_FOUND` | The wrong folder was deployed. Deploy from `build/web`. |
| Map does not load on web | Add the Vercel domain to the Google Maps key's allowed referrers. |
| Push does nothing on web | Push is mobile-only and is skipped on web. |

## 🗺️ Roadmap

- 🚑 Integration with real emergency services and official alert channels
- 🏛️ Nearest police station lookup with real data
- 💬 SMS fallback for contacts without the app
- 🔔 Push notifications on web
- 🌏 Khmer and English language support
- 🧪 Automated tests and CI

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines
- Keep changes focused and well described
- Test with the checklist above
- Update documentation as needed
- Never commit secrets

## 📞 Support

If you encounter any issues or have questions:

- 🐛 Issues: [GitHub Issues](https://github.com/mean1718/PersonalSafetyCheck-in/issues)
- 📚 Documentation: this README

## 📄 License

This project was built for academic and educational purposes as part of the NEXT-GEN ENGAGEMENT PROGRAM, Batch III.

## 🙏 Acknowledgments

- **NEXT-GEN ENGAGEMENT PROGRAM - BATCH III** - Organizer of this program

**Advisors**
- Mr. Meng Navid
- Ms. Moch Sreyny
- Ms. Phan Pornlea

**Mentor**
- Ms. Met Sokcheat

**Development Team - Group 2**
- Dan Thidamorokat - Team Collaborator
- Lenh Sokmean - Team Collaborator
- Kong Theara - Team Collaborator
- Lay Viza - Team Collaborator
- Kong Monineath - Team Collaborator
- Sophan Sotheany - Team Collaborator
- Noeun Linda - Team Collaborator

- Open Source Community for the amazing libraries and tools
  
We would like to thank the organizers, advisors, mentor, team members, and open-source community for their support and contributions to the SafetyU project.🙏❤️
---

Made with ❤️ by **Group 2**, SafetyU Team
