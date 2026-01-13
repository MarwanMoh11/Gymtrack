'use client';

import { useUser } from '@/context/user-context';
import type { Exercise } from '@/types/workout';
import { useMemo } from 'react';

export const useExercise = (exerciseId: string): Exercise | undefined => {
    const { userData } = useUser();

    return useMemo(() => {
        if (!exerciseId) return undefined;

        // 1. Search in the user's active plan first (most likely place)
        const activePlan = userData?.plans.find((p: import('@/types/workout').NamedWorkoutPlan) => p.isActive);
        if (activePlan) {
            for (const day of activePlan.plan) {
                const found = day.exercises.find((ex: Exercise) => ex.id === exerciseId);
                if (found) return found;
            }
        }

        // 2. Search in all user plans
        if (userData?.plans) {
            for (const plan of userData.plans) {
                for (const day of plan.plan) {
                    const found = day.exercises.find((ex: Exercise) => ex.id === exerciseId);
                    if (found) return found;
                }
            }
        }

        return undefined;

    }, [userData, exerciseId]);
};
