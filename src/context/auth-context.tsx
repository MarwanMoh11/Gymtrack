// src/context/auth-context.tsx
'use client';

import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import {
  onAuthStateChanged,
  User,
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { useQueryClient } from '@tanstack/react-query';
import { initializeDefaultPlansForUser } from '@/lib/firestore-workout-plan-service';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<any>;
  signup: (email: string, password: string) => Promise<any>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const queryClient = useQueryClient();

  useEffect(() => {
    console.log('[AuthContext] Setting up onAuthStateChanged listener.');
    const unsubscribe = onAuthStateChanged(auth, async (newUser) => {
      const isNewUser = newUser && newUser.metadata.creationTime === newUser.metadata.lastSignInTime;
      console.log(`[AuthContext] onAuthStateChanged triggered. User: ${newUser?.uid || 'null'}. Is new user: ${isNewUser}`);

      setUser(newUser);

      if (isNewUser) {
        console.log('[AuthContext] New user detected. Initializing default plans.');
        await initializeDefaultPlansForUser();
        // After initializing, we should refetch the plans query to ensure the app has the latest state.
        await queryClient.invalidateQueries({ queryKey: ['workoutPlans'] });
      }

      if (!newUser) {
        console.log('[AuthContext] User logged out. Clearing all query data.');
        // Clearing the entire cache on logout is safe and ensures no stale data for the next user.
        queryClient.clear();
      }
      
      console.log('[AuthContext] Auth loading state set to false.');
      setLoading(false);
    });

    return () => {
      console.log('[AuthContext] Cleaning up onAuthStateChanged listener.');
      unsubscribe();
    }
  }, [queryClient]);

  const login = (email: string, password: string) => {
    console.log('[AuthContext] Attempting login for email:', email);
    return signInWithEmailAndPassword(auth, email, password);
  };

  const signup = async (email: string, password: string) => {
    console.log('[AuthContext] Attempting signup for email:', email);
    // The onAuthStateChanged listener will handle the user state update and plan initialization.
    return createUserWithEmailAndPassword(auth, email, password);
  };

  const logout = async () => {
    console.log('[AuthContext] Attempting logout for user:', user?.uid);
    await signOut(auth);
  };

  const value = {
    user,
    loading,
    login,
    signup,
    logout,
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
