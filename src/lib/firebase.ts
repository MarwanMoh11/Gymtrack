
// src/lib/firebase.ts
import { initializeApp, getApps, getApp } from "firebase/app";
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

// Initialize Firebase
// To prevent reinitialization on hot reloads in development, check if an app is already initialized.
const app = !getApps().length ? initializeApp(firebaseConfig) : getApp();
const auth = getAuth(app);
const db = getFirestore(app);

export { app, auth, db };
