// src/lib/firebase.ts
import { initializeApp, getApps, getApp, type FirebaseApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";

const firebaseConfig = {
  apiKey: "REDACTED_FIREBASE_API_KEY",
  authDomain: "REDACTED_FIREBASE_PROJECT.firebaseapp.com",
  projectId: "REDACTED_FIREBASE_PROJECT",
  storageBucket: "REDACTED_FIREBASE_PROJECT.appspot.com",
  messagingSenderId: "REDACTED_SENDER_ID",
  appId: "1:REDACTED_SENDER_ID:web:REDACTED_APP_ID",
};

// --- Singleton Pattern for Firebase Initialization ---
let app: FirebaseApp;
let auth: ReturnType<typeof getAuth>;
let db: ReturnType<typeof getFirestore>;

if (getApps().length === 0) {
  console.log("FIREBASE_INIT: No Firebase apps initialized. Creating a new one.");
  try {
    app = initializeApp(firebaseConfig);
    console.log("FIREBASE_INIT: New app created successfully. Project ID:", app.options.projectId);
  } catch (error) {
    console.error("FIREBASE_INIT: FATAL: Firebase initialization failed.", error);
    app = null as any; // Avoid further errors
  }
} else {
  console.log("FIREBASE_INIT: Firebase app already exists. Getting existing app.");
  app = getApp();
  console.log("FIREBASE_INIT: Existing app retrieved. Project ID:", app.options.projectId);
}

// Initialize services only if app is valid
if (app) {
    auth = getAuth(app);
    db = getFirestore(app);
    console.log("FIREBASE_INIT: Auth and Firestore services initialized for app:", app.name);
} else {
    console.error("FIREBASE_INIT: Cannot initialize Auth/Firestore because app is invalid.");
    auth = null as any;
    db = null as any;
}

export { app, auth, db };
