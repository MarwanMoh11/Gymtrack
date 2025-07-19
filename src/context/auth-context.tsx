
'use client';

import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import {
  getAuth,
  onAuthStateChanged,
  User,
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';
import { app } from '@/lib/firebase'; // Ensure your firebase init file is correctly referenced

// Pass the initialized app to getAuth to ensure context is correct.
const auth = getAuth(app);

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

  console.log("AUTH_CONTEXT: AuthProvider component is mounting/rendering.");
  if (!auth) {
    console.error("AUTH_CONTEXT: CRITICAL - Auth object is null or undefined at provider level.");
  } else {
    console.log("AUTH_CONTEXT: Auth object is available at provider level. App:", auth.app.name);
  }

  useEffect(() => {
    console.log("AUTH_CONTEXT_EFFECT: Setting up onAuthStateChanged listener.");
    const unsubscribe = onAuthStateChanged(auth, (user) => {
      console.log(`AUTH_CONTEXT_EFFECT: onAuthStateChanged triggered. User found: ${!!user}. Email: ${user ? user.email : 'null'}`);
      setUser(user);
      setLoading(false);
      console.log("AUTH_CONTEXT_EFFECT: State updated. Loading:", false, "User:", user ? user.uid : null);
    });

    return () => {
      console.log("AUTH_CONTEXT_EFFECT: Cleaning up onAuthStateChanged listener.");
      unsubscribe();
    }
  }, []);

  const login = (email: string, password: string) => {
    console.log(`AUTH_CONTEXT_ACTION: Attempting login for email: ${email}.`);
    if (!auth?.app?.options?.apiKey) {
      console.error("AUTH_CONTEXT_ACTION: CRITICAL - Auth object is missing API key before login call.");
    }
    return signInWithEmailAndPassword(auth, email, password);
  };

  const signup = (email: string, password: string) => {
    console.log(`AUTH_CONTEXT_ACTION: Attempting signup for email: ${email}.`);
    console.log("AUTH_CONTEXT_ACTION: Checking auth object before signup call:", auth);
    if (!auth?.app?.options?.apiKey) {
      console.error("AUTH_CONTEXT_ACTION: CRITICAL - Auth object is missing API key before signup call.");
    }
    return createUserWithEmailAndPassword(auth, email, password);
  };

  const logout = () => {
    console.log("AUTH_CONTEXT_ACTION: Attempting logout.");
    if (!auth?.app?.options?.apiKey) {
      console.error("AUTH_CONTEXT_ACTION: CRITICAL - Auth object is missing API key before logout call.");
    }
    return signOut(auth);
  };

  const value = {
    user,
    loading,
    login,
    signup,
    logout,
  };

  console.log("AUTH_CONTEXT: Value provided to context:", { loading, user: user ? user.uid : null });

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
