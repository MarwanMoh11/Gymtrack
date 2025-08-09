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
import { getUserData, initializeUserData } from '@/lib/firestore-workout-plan-service';

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
      console.log(`[AuthContext] onAuthStateChanged triggered. User: ${newUser?.uid || 'null'}.`);
      
      if (newUser) {
        // Check if user data exists in Firestore.
        const userData = await getUserData(newUser.uid);
        if (!userData) {
          console.log('[AuthContext] New user detected or missing data. Initializing user data in Firestore.');
          await initializeUserData(newUser.uid);
          // After initializing, invalidate to ensure AppLayout re-fetches the new user data.
          await queryClient.invalidateQueries({ queryKey: ['userData', newUser.uid] });
        }
      } else {
        console.log('[AuthContext] User logged out. Clearing all user-specific query data.');
        // Clear all queries upon logout to prevent stale data issues.
        queryClient.clear();
      }

      setUser(newUser);
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
    // The onAuthStateChanged listener now handles the user data initialization.
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
