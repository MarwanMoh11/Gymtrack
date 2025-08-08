// src/lib/firebase.ts
import { initializeApp, getApps, getApp, type FirebaseApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";
import { config } from 'dotenv';

// Ensure environment variables are loaded
config({ path: '.env.local' });


// This configuration is now driven by your .env.local file.
const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

// Initialize Firebase App
// Check if all required config values are present before initializing
let app: FirebaseApp;
const requiredConfig = [firebaseConfig.apiKey, firebaseConfig.authDomain, firebaseConfig.projectId];
if (requiredConfig.every(value => Boolean(value))) {
    app = getApps().length ? getApp() : initializeApp(firebaseConfig);
} else {
    console.warn("Firebase configuration is missing or incomplete. Please check your .env.local file. App functionality will be limited.");
    // Provide a mock app object so the rest of the app doesn't crash on import
    app = getApps().length ? getApp() : ({ options: {} } as FirebaseApp);
}


// Initialize other Firebase services
const auth = getAuth(app);
const db = getFirestore(app);

// Export the initialized services for use in other parts of the application.
export { app, auth, db };
