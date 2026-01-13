'use client';

import { useUser } from '@/context/user-context';
import { exerciseLibrary } from '@/data/workout-data';
import type { Exercise } from '@/types/workout';
import { useMemo } from 'react';

export const useActivePlan = () => {
    const { activePlan, isLoading } = useUser();
    return { activePlan, isLoading };
};

export const useUserPlans = () => {
    const { userData, isLoading, updatePlan, setActivePlan } = useUser();
    return {
        plans: userData?.plans ?? [],
        isLoading,
        updatePlan,
        setActivePlan
    };
};

export const useExercise = (exerciseId: string): Exercise | undefined => {
    const { userData } = useUser();

    return useMemo(() => {
        if (!exerciseId) return undefined;

        // 1. Search in the user's active plan first (most likely place)
        const activePlan = userData?.plans.find(p => p.isActive);
        if (activePlan) {
            for (const day of activePlan.plan) {
                const found = day.exercises.find(ex => ex.id === exerciseId);
                if (found) return found;
            }
        }

        // 2. Search in all user plans
        if (userData?.plans) {
            for (const plan of userData.plans) {
                for (const day of plan.plan) {
                    const found = day.exercises.find(ex => ex.id === exerciseId);
                    if (found) return found;
                }
            }
        }

        // 3. Fallback to the static library
        // Assuming exerciseLibrary is available locally or we fetch it. 
        // In strict auth mode, we might want to fetch this from DB too, 
        // but for now keeping library static is fine as refined in plan.
        const libraryExercise = exerciseLibrary[0].exercises.find(ex => ex.id === exerciseId);
        return libraryExercise;

    }, [userData, exerciseId]);
};

export const useAllExercises = (): Exercise[] => {
    const { userData } = useUser();

    return useMemo(() => {
        const allExercisesMap = new Map<string, Exercise>();

        // Add exercises from user plans
        userData?.plans.forEach(plan => {
            plan.plan.forEach(day => {
                day.exercises.forEach(ex => {
                    if (!allExercisesMap.has(ex.id)) {
                        allExercisesMap.set(ex.id, ex);
                    }
                });
            });
        });

        // Add exercises from library
        exerciseLibrary[0].exercises.forEach(ex => {
            if (!allExercisesMap.has(ex.id)) {
                allExercisesMap.set(ex.id, ex);
            }
        });

        return Array.from(allExercisesMap.values()).sort((a, b) => a.name.localeCompare(b.name));
    }, [userData]);
}
