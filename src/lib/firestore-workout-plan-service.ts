// src/lib/firestore-workout-plan-service.ts

import { db } from '@/lib/firebase';
import { doc, getDoc, setDoc, collection, getDocs, query, orderBy } from 'firebase/firestore';
import type { NamedWorkoutPlan, UserData, GlobalExercise } from '../types/workout';
import { defaultNamedPlans } from '../data/default-plans';

/**
 * Retrieves the user data document, which contains workout plans and onboarding status.
 * @param userId The ID of the user.
 * @returns The UserData object or null if not found.
 */
export async function getUserData(userId: string): Promise<UserData | null> {
    if (!userId) return null;
    const userDocRef = doc(db, 'users', userId);
    try {
        const docSnap = await getDoc(userDocRef);
        if (docSnap.exists()) {
            return docSnap.data() as UserData;
        }
        return null;
    } catch (error) {
        console.error("Error getting user data:", error);
        throw new Error("Failed to fetch user data.");
    }
}

/**
 * Initializes the user document with default workout plans and sets onboarding status.
 * This should be called once upon user signup if their document doesn't exist.
 * @param userId The ID of the new user.
 * @param email The email of the new user.
 * @returns The newly created UserData object.
 */
export async function initializeUserData(userId: string, email: string = ''): Promise<UserData> {
    console.log(`[PlanService] Initializing user data and default plans for new user: ${userId} (${email})`);
    if (!userId) {
        throw new Error("User ID is required to initialize user data.");
    }

    const userData: UserData = {
        uid: userId,
        email: email || '', // Ensure no undefined
        onboardingStatus: 'needs_plan_selection',
        // Set the first plan as active by default
        plans: defaultNamedPlans.map((p, index: number) => ({ ...p, isActive: index === 0 })),
    };

    const userDocRef = doc(db, 'users', userId);
    await setDoc(userDocRef, userData);
    console.log(`[PlanService] User document created for ${userId}`);
    return userData;
}

/**
 * Saves the entire user data object to Firestore.
 * This is the primary way to update a user's plans or onboarding status.
 * @param userId The ID of the user.
 * @param userData The full UserData object to save.
 */
export async function saveUserData(userId: string, userData: UserData): Promise<void> {
    console.log(`[PlanService] Saving user data for user ID: ${userId}`);
    if (!userId) {
        throw new Error("User ID is required to save data.");
    }
    const userDocRef = doc(db, 'users', userId);
    await setDoc(userDocRef, userData, { merge: true });
    console.log(`[PlanService] Successfully saved user data for ${userId}.`);
}

// --- Global Exercise Library Functions ---

/**
 * Fetches all global exercises from the read-only library.
 * This is cached by Firestore, but we should consider client-side caching if the list grows huge.
 */
export async function getGlobalExercises(): Promise<GlobalExercise[]> {
    console.log('[PlanService] Fetching global exercises...');
    try {
        const globalRef = collection(db, 'globalExercises');
        // Order by name for easy display
        const q = query(globalRef, orderBy('name'));
        const snapshot = await getDocs(q);

        const exercises = snapshot.docs.map(doc => doc.data() as GlobalExercise);
        console.log(`[PlanService] Fetched ${exercises.length} global exercises.`);
        return exercises;
    } catch (error) {
        console.error("Error fetching global exercises:", error);
        // Fallback to local data if offline or error, though for this architecture we strictly want remote
        // But for dev speed, we can return empty or throw
        return [];
    }
}

/**
 * Helper to get a single global exercise by ID.
 * Useful for restoring full objects from just an ID in a plan.
 */
export async function getGlobalExerciseById(exerciseId: string): Promise<GlobalExercise | null> {
    if (!exerciseId) return null;
    try {
        const docRef = doc(db, 'globalExercises', exerciseId);
        const docSnap = await getDoc(docRef);
        if (docSnap.exists()) {
            return docSnap.data() as GlobalExercise;
        }
        return null;
    } catch (error) {
        console.error(`Error fetching global exercise ${exerciseId}:`, error);
        return null;
    }
}
