// src/lib/firebase.ts
import { initializeApp, getApps, getApp, type FirebaseApp } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";

// This configuration is now driven by your .env file.
const firebaseConfig = {
    apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY || "AIza-build-time-placeholder",
    authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN || "gymtrack-placeholder.firebaseapp.com",
    projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID || "gymtrack-placeholder",
    storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET || "gymtrack-placeholder.appspot.com",
    messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID || "000000000000",
    appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID || "1:000000000000:web:000000000000",
};

// Initialize Firebase App
// We allow initialization even with missing keys during build to prevent prerender crashes.
const app = getApps().length ? getApp() : initializeApp(firebaseConfig);

if (!process.env.NEXT_PUBLIC_FIREBASE_API_KEY && typeof window !== 'undefined') {
    console.warn("Firebase configuration is missing. Please check your environment variables.");
}


// Initialize other Firebase services
const auth = getAuth(app);
const db = getFirestore(app);

// Export the initialized services for use in other parts of the application.
export { app, auth, db };
