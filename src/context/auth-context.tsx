// src/context/auth-context.tsx
'use client';

import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import {
  onAuthStateChanged,
  User,
  createUserWithEmailAndPassword,
  signInWithEmailAndPassword,
  signOut,
  GoogleAuthProvider,
  signInWithPopup,
  getAdditionalUserInfo,
  updateProfile as firebaseUpdateProfile,
  reauthenticateWithCredential,
  reauthenticateWithPopup,
  EmailAuthProvider,
  deleteUser,
} from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { useQueryClient } from '@tanstack/react-query';
import { getUserData, initializeUserData } from '@/lib/firestore-workout-plan-service';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<any>;
  signup: (email: string, password: string) => Promise<any>;
  signInWithGoogle: () => Promise<any>;
  logout: () => Promise<void>;
  updateProfile: (data: { displayName?: string; photoURL?: string }) => Promise<void>;
  deleteAccount: (password?: string) => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const queryClient = useQueryClient();

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (newUser) => {
      setUser(newUser);
      
      if (!newUser) {
        queryClient.clear();
      } else {
        const existingData = await getUserData(newUser.uid);
        if (!existingData) {
          await initializeUserData(newUser.uid);
          await queryClient.invalidateQueries({ queryKey: ['userData', newUser.uid] });
        }
      }

      setLoading(false);
    });

    return () => unsubscribe();
  }, [queryClient]);

  const login = (email: string, password: string) => {
    return signInWithEmailAndPassword(auth, email, password);
  };
  
  const signInWithGoogle = async () => {
    const provider = new GoogleAuthProvider();
    try {
        const result = await signInWithPopup(auth, provider);
        const additionalUserInfo = getAdditionalUserInfo(result);
        
        if (additionalUserInfo?.isNewUser) {
            await initializeUserData(result.user.uid);
            await queryClient.invalidateQueries({ queryKey: ['userData', result.user.uid] });
        }
        return result;
    } catch (error) {
        console.error("Google Sign-In Error:", error);
        throw error;
    }
  };

  const signup = async (email: string, password: string) => {
    const userCredential = await createUserWithEmailAndPassword(auth, email, password);
    await initializeUserData(userCredential.user.uid);
    await queryClient.invalidateQueries({ queryKey: ['userData', userCredential.user.uid] });
    return userCredential;
  };

  const logout = async () => {
    await signOut(auth);
  };
  
  const updateProfile = async (data: { displayName?: string; photoURL?: string }) => {
    if (!auth.currentUser) throw new Error("Not authenticated");
    await firebaseUpdateProfile(auth.currentUser, data);
    // Manually update the user state to reflect changes immediately
    setUser(auth.currentUser);
    // You might also want to update the user data in Firestore if you store it there too.
    // await saveUserData(auth.currentUser.uid, { displayName: data.displayName });
    // And invalidate any related queries
    queryClient.invalidateQueries({ queryKey: ['user', auth.currentUser.uid] });
  };
  
  const reauthenticate = async (password: string) => {
    if (!auth.currentUser || !auth.currentUser.email) throw new Error("No user or email found for reauthentication.");
    const credential = EmailAuthProvider.credential(auth.currentUser.email, password);
    await reauthenticateWithCredential(auth.currentUser, credential);
  };
  
  const deleteAccount = async (password?: string) => {
      const currentUser = auth.currentUser;
      if (!currentUser) throw new Error("Not authenticated");

      const providerId = currentUser.providerData[0]?.providerId;

      try {
        if (providerId === 'password' && password) {
          await reauthenticate(password);
        } else if (providerId === 'google.com') {
          const provider = new GoogleAuthProvider();
          await reauthenticateWithPopup(currentUser, provider); // This re-authenticates
        } else {
            // This case handles users who might have a password but are trying to delete without one
            // or other unhandled providers.
            if(password) await reauthenticate(password);
            else throw new Error("Re-authentication required.");
        }
        
        // If re-authentication was successful, proceed with deletion
        await deleteUser(currentUser);
        setUser(null);
        queryClient.clear();
      } catch (error: any) {
          console.error("Error during account deletion process:", error);
           if (error.code === 'auth/requires-recent-login' && providerId === 'google.com') {
              // This error means the initial token from Google is too old. 
              // We need to force a fresh popup.
              try {
                await reauthenticateWithPopup(auth.currentUser!, new GoogleAuthProvider());
                await deleteUser(currentUser); // Retry deletion
                setUser(null);
                queryClient.clear();
              } catch (reauthError) {
                  throw reauthError; // Throw the re-authentication error
              }
           } else {
             throw error; // Throw other errors (e.g., wrong password)
           }
      }
  };


  const value = {
    user,
    loading,
    login,
    signup,
    signInWithGoogle,
    logout,
    updateProfile,
    deleteAccount,
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
