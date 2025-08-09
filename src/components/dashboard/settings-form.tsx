// src/components/dashboard/settings-form.tsx
'use client';

import { useState, useEffect, useCallback } from 'react';
import { useAuth } from '@/context/auth-context';
import { useForm, Controller } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useTheme } from 'next-themes';
import { Card, CardHeader, CardContent, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { useToast } from '@/hooks/use-toast';
import { Loader2, User, Palette, ShieldAlert, LogOut, Trash2 } from 'lucide-react';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { useMutation } from '@tanstack/react-query';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";


const profileSchema = z.object({
  displayName: z.string().min(2, { message: "Name must be at least 2 characters." }).max(50, { message: "Name cannot be longer than 50 characters." }),
});
type ProfileFormValues = z.infer<typeof profileSchema>;

export default function SettingsForm() {
  const { user, updateProfile, reauthenticate, deleteAccount } = useAuth();
  const { toast } = useToast();
  const { setTheme, theme } = useTheme();

  const [isProfileLoading, setIsProfileLoading] = useState(false);
  const [isDeleteLoading, setIsDeleteLoading] = useState(false);
  const [passwordForDelete, setPasswordForDelete] = useState('');

  const form = useForm<ProfileFormValues>({
    resolver: zodResolver(profileSchema),
    defaultValues: {
      displayName: user?.displayName || '',
    },
  });

  useEffect(() => {
    if (user) {
      form.reset({ displayName: user.displayName || '' });
    }
  }, [user, form]);

  const updateProfileMutation = useMutation({
    mutationFn: (data: { displayName: string }) => {
        setIsProfileLoading(true);
        return updateProfile(data);
    },
    onSuccess: () => {
        toast({ title: 'Profile Updated', description: 'Your profile information has been successfully updated.' });
    },
    onError: (error: any) => {
        toast({ variant: 'destructive', title: 'Update Failed', description: error.message || "An unexpected error occurred." });
    },
    onSettled: () => {
        setIsProfileLoading(false);
    }
  });

  const deleteAccountMutation = useMutation({
    mutationFn: async () => {
        setIsDeleteLoading(true);
        if (!passwordForDelete) throw new Error("Password is required to delete your account.");
        await reauthenticate(passwordForDelete);
        await deleteAccount();
    },
    onSuccess: () => {
        toast({ title: 'Account Deleted', description: 'Your account has been permanently deleted.' });
        // The AppLayout will handle the redirect to /login
    },
    onError: (error: any) => {
        let description = "An unexpected error occurred.";
        if (error.code === 'auth/wrong-password' || error.code === 'auth/invalid-credential') {
            description = "The password you entered is incorrect. Please try again.";
        } else if(error.code === 'auth/requires-recent-login'){
            description = "This is a sensitive operation and requires a recent login. Please log out and log back in to delete your account."
        }
        toast({ variant: 'destructive', title: 'Deletion Failed', description });
    },
    onSettled: () => {
        setIsDeleteLoading(false);
        setPasswordForDelete('');
    }
  });

  const onProfileSubmit = (data: ProfileFormValues) => {
    updateProfileMutation.mutate(data);
  };
  
  const getInitials = (name: string | null | undefined) => {
    if (!name) return "U";
    return name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
  };


  return (
    <div className="container mx-auto max-w-3xl py-8 px-4 md:px-6 space-y-8">
        <div className="space-y-2">
            <h1 className="text-3xl font-bold text-primary">Settings</h1>
            <p className="text-muted-foreground">Manage your account and app preferences.</p>
        </div>

        {/* --- Profile Card --- */}
        <Form {...form}>
            <form onSubmit={form.handleSubmit(onProfileSubmit)}>
            <Card>
                <CardHeader>
                    <div className="flex items-center gap-3">
                        <User className="h-6 w-6 text-primary/80" />
                        <CardTitle>Profile</CardTitle>
                    </div>
                    <CardDescription>This is your public display name.</CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                    <div className="flex items-center gap-4">
                        <Avatar className="h-20 w-20">
                            <AvatarImage src={user?.photoURL || undefined} alt={user?.displayName || 'User'}/>
                            <AvatarFallback className="text-2xl">{getInitials(user?.displayName)}</AvatarFallback>
                        </Avatar>
                        <Button type="button" variant="outline" disabled>
                            Upload Photo (coming soon)
                        </Button>
                    </div>

                    <div className="space-y-1">
                        <Label htmlFor="displayName">Display Name</Label>
                        <Controller
                            name="displayName"
                            control={form.control}
                            render={({ field }) => (
                                <Input id="displayName" {...field} disabled={isProfileLoading} />
                            )}
                        />
                        {form.formState.errors.displayName && <p className="text-sm text-destructive mt-1">{form.formState.errors.displayName.message}</p>}
                    </div>
                </CardContent>
                <CardFooter className="border-t px-6 py-4 flex justify-end">
                    <Button type="submit" disabled={isProfileLoading}>
                        {isProfileLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                        Save Changes
                    </Button>
                </CardFooter>
            </Card>
            </form>
        </Form>
        
        {/* --- Appearance Card --- */}
        <Card>
             <CardHeader>
                <div className="flex items-center gap-3">
                    <Palette className="h-6 w-6 text-primary/80" />
                    <CardTitle>Appearance</CardTitle>
                </div>
                <CardDescription>Customize the look and feel of the app.</CardDescription>
            </CardHeader>
            <CardContent>
                <div className="grid gap-2">
                     <Label htmlFor="theme">Theme</Label>
                     <Select value={theme} onValueChange={setTheme}>
                        <SelectTrigger id="theme">
                           <SelectValue placeholder="Select theme" />
                        </SelectTrigger>
                        <SelectContent>
                           <SelectItem value="light">Light</SelectItem>
                           <SelectItem value="dark">Dark</SelectItem>
                           <SelectItem value="system">System</SelectItem>
                        </SelectContent>
                     </Select>
                </div>
            </CardContent>
        </Card>

        {/* --- Danger Zone --- */}
        <Card className="border-destructive">
             <CardHeader>
                <div className="flex items-center gap-3 text-destructive">
                    <ShieldAlert className="h-6 w-6" />
                    <CardTitle>Danger Zone</CardTitle>
                </div>
            </CardHeader>
            <CardContent>
                <h3 className="font-semibold text-md mb-2">Delete Account</h3>
                <p className="text-sm text-muted-foreground mb-4">
                    Once you delete your account, there is no going back. All of your data, including workout plans and logs, will be permanently removed. Please be certain.
                </p>
                <AlertDialog>
                    <AlertDialogTrigger asChild>
                        <Button variant="destructive">
                            <Trash2 className="mr-2 h-4 w-4" /> Delete Account
                        </Button>
                    </AlertDialogTrigger>
                    <AlertDialogContent>
                        <AlertDialogHeader>
                            <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
                            <AlertDialogDescription>
                                This action cannot be undone. This will permanently delete your account and remove all your data from our servers. To confirm, please type your current password.
                            </AlertDialogDescription>
                        </AlertDialogHeader>
                        <div className="py-2">
                             <Label htmlFor="password-confirm" className="sr-only">Password</Label>
                             <Input 
                                id="password-confirm" 
                                type="password"
                                placeholder="Enter your password to confirm"
                                value={passwordForDelete}
                                onChange={(e) => setPasswordForDelete(e.target.value)}
                             />
                        </div>
                        <AlertDialogFooter>
                            <AlertDialogCancel disabled={isDeleteLoading}>Cancel</AlertDialogCancel>
                            <AlertDialogAction 
                                onClick={() => deleteAccountMutation.mutate()} 
                                className="bg-destructive hover:bg-destructive/90"
                                disabled={isDeleteLoading || !passwordForDelete}
                            >
                                {isDeleteLoading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                                Delete My Account
                            </AlertDialogAction>
                        </AlertDialogFooter>
                    </AlertDialogContent>
                </AlertDialog>
            </CardContent>
        </Card>
    </div>
  );
}
