'use client';

import React, { createContext, useContext, ReactNode, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { getUserData, saveUserData, initializeUserData } from '@/lib/firestore-workout-plan-service';
import type { UserData, NamedWorkoutPlan, WorkoutDay } from '@/types/workout';

interface UserContextType {
    userData: UserData | null;
    isLoading: boolean;
    error: unknown;
    activePlan: NamedWorkoutPlan | undefined;
    updatePlan: (planId: string, updates: Partial<NamedWorkoutPlan>) => Promise<void>;
    setActivePlan: (planId: string) => Promise<void>;
    refreshUserData: () => Promise<void>;
}

const UserContext = createContext<UserContextType | undefined>(undefined);

export const UserProvider = ({ children }: { children: ReactNode }) => {
    const { user } = useAuth();
    const queryClient = useQueryClient();

    // Fetch user data
    const { data: userData, isLoading, error, refetch } = useQuery({
        queryKey: ['userData', user?.uid],
        queryFn: async () => {
            if (!user?.uid) return null;
            const data = await getUserData(user.uid);
            if (!data) {
                // If no data exists, initialize it (fallback for safety)
                return await initializeUserData(user.uid);
            }
            return data;
        },
        enabled: !!user?.uid,
        staleTime: 1000 * 60 * 5, // 5 minutes
    });

    // Mutation to save user data
    const saveMutation = useMutation({
        mutationFn: async (newData: UserData) => {
            if (!user?.uid) throw new Error("No user");
            await saveUserData(user.uid, newData);
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['userData', user?.uid] });
        },
    });

    const activePlan = userData?.plans.find(p => p.isActive);

    const updatePlan = useCallback(async (planId: string, updates: Partial<NamedWorkoutPlan>) => {
        if (!userData || !user?.uid) return;

        const updatedPlans = userData.plans.map(p =>
            p.id === planId ? { ...p, ...updates } : p
        );

        const newUserData = { ...userData, plans: updatedPlans };
        await saveMutation.mutateAsync(newUserData);
    }, [userData, user, saveMutation]);

    const setActivePlan = useCallback(async (planId: string) => {
        if (!userData || !user?.uid) return;

        const updatedPlans = userData.plans.map(p => ({
            ...p,
            isActive: p.id === planId
        }));

        const newUserData = { ...userData, plans: updatedPlans };
        await saveMutation.mutateAsync(newUserData);
    }, [userData, user, saveMutation]);

    const refreshUserData = async () => {
        await refetch();
    };

    const value = {
        userData: userData ?? null,
        isLoading,
        error,
        activePlan,
        updatePlan,
        setActivePlan,
        refreshUserData
    };

    return (
        <UserContext.Provider value={value}>
            {children}
        </UserContext.Provider>
    );
};

export const useUser = () => {
    const context = useContext(UserContext);
    if (context === undefined) {
        throw new Error('useUser must be used within a UserProvider');
    }
    return context;
};
