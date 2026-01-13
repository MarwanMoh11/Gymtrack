// src/lib/firestore-workout-plan-service.ts

import { db } from '@/lib/firebase';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import type { NamedWorkoutPlan, UserData } from '@/types/workout';
import { defaultNamedPlans } from '@/data/workout-data';

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
 * @returns The newly created UserData object.
 */
export async function initializeUserData(userId: string): Promise<UserData> {
    console.log(`[PlanService] Initializing user data and default plans for new user: ${userId}`);
    if (!userId) {
        throw new Error("User ID is required to initialize user data.");
    }

    const userData: UserData = {
        id: userId,
        onboardingStatus: 'needs_plan_selection',
        // Set the first plan as active by default
        plans: defaultNamedPlans.map((p, index) => ({ ...p, isActive: index === 0 })),
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
