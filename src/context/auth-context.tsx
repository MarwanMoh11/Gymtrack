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
    const unsubscribe = onAuthStateChanged(auth, async (user) => {
      console.log('[AuthContext] onAuthStateChanged triggered. User:', user?.uid || 'null');
      setUser(user);
      if (user) {
        // This is a good place to ensure plans are initialized for a new user if they don't exist.
        // We can check localStorage here.
        const plansExist = localStorage.getItem('gymtrack_workout_plans');
        if (!plansExist) {
          console.log('[AuthContext] No plans found in localStorage for new/logged-in user. Initializing default plans.');
          await initializeDefaultPlansForUser();
        }
      } else {
        console.log('[AuthContext] User logged out. Clearing query cache.');
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
