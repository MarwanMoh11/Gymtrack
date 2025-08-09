// src/app/dashboard/settings/loading.tsx
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardHeader, CardContent, CardFooter } from "@/components/ui/card";
import { User, Palette, ShieldAlert } from "lucide-react";

export default function LoadingSettingsPage() {
  return (
    <div className="container mx-auto max-w-3xl py-8 px-4 md:px-6 space-y-8">
      <div className="space-y-2">
        <h1 className="text-3xl font-bold text-primary">Settings</h1>
        <p className="text-muted-foreground">Manage your account and app preferences.</p>
      </div>

      {/* Profile Card Skeleton */}
      <Card>
        <CardHeader>
          <div className="flex items-center gap-3">
            <User className="h-6 w-6 text-primary/80" />
            <h2 className="text-xl font-semibold">Profile</h2>
          </div>
          <p className="text-sm text-muted-foreground">Update your public profile information.</p>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center gap-4">
            <Skeleton className="h-20 w-20 rounded-full" />
            <div className="flex-grow space-y-2">
              <Skeleton className="h-9 w-full" />
              <Skeleton className="h-4 w-1/2" />
            </div>
          </div>
          <div className="space-y-2">
            <Skeleton className="h-4 w-1/4" />
            <Skeleton className="h-9 w-full" />
          </div>
        </CardContent>
        <CardFooter className="border-t px-6 py-4 flex justify-end">
          <Skeleton className="h-9 w-24" />
        </CardFooter>
      </Card>

      {/* Appearance Card Skeleton */}
      <Card>
        <CardHeader>
           <div className="flex items-center gap-3">
            <Palette className="h-6 w-6 text-primary/80" />
            <h2 className="text-xl font-semibold">Appearance</h2>
          </div>
          <p className="text-sm text-muted-foreground">Customize the look and feel of the app.</p>
        </CardHeader>
        <CardContent>
            <Skeleton className="h-4 w-1/4 mb-2" />
            <Skeleton className="h-10 w-full" />
        </CardContent>
      </Card>
      
       {/* Danger Zone Card Skeleton */}
      <Card className="border-destructive">
        <CardHeader>
           <div className="flex items-center gap-3">
            <ShieldAlert className="h-6 w-6 text-destructive" />
            <h2 className="text-xl font-semibold text-destructive">Danger Zone</h2>
          </div>
        </CardHeader>
        <CardContent className="space-y-3">
          <h3 className="text-md font-semibold">Delete Account</h3>
           <p className="text-sm text-muted-foreground">
              Once you delete your account, there is no going back. All of your data, including workout plans and logs, will be permanently removed.
          </p>
           <Skeleton className="h-9 w-32" />
        </CardContent>
      </Card>
    </div>
  );
}
