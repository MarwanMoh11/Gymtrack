// src/app/onboarding/choose-plan/page.tsx
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { getUserData, saveUserData } from '@/lib/firestore-workout-plan-service';
import type { NamedWorkoutPlan, UserData } from '@/types/workout';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { CheckCircle, Loader2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { Skeleton } from '@/components/ui/skeleton';

function LoadingSkeleton() {
    return (
        <div className="flex flex-col items-center justify-center min-h-screen bg-background p-4">
            <div className="w-full max-w-3xl space-y-8">
                <div className="text-center space-y-2">
                    <Skeleton className="h-10 w-3/4 mx-auto" />
                    <Skeleton className="h-5 w-1/2 mx-auto" />
                </div>
                <div className="space-y-4">
                    {[...Array(3)].map((_, i) => (
                        <Card key={i} className="bg-card/50">
                            <CardHeader>
                                <Skeleton className="h-6 w-1/2" />
                                <Skeleton className="h-4 w-full mt-2" />
                            </CardHeader>
                        </Card>
                    ))}
                </div>
            </div>
        </div>
    );
}

export default function ChoosePlanPage() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const router = useRouter();
  const { toast } = useToast();
  const [selectedPlanId, setSelectedPlanId] = useState<string | null>(null);

  const { data: userData, isLoading: isLoadingUserData } = useQuery({
    queryKey: ['userData', user?.uid],
    queryFn: () => getUserData(user!.uid),
    enabled: !!user,
  });

  const mutation = useMutation({
    mutationFn: (newUserData: UserData) => saveUserData(user!.uid, newUserData),
    onSuccess: (data, newUserData) => {
        console.log("[ChoosePlanPage] 🟢 Mutation SUCCEEDED.");
        // Manually update the query cache with the new user data.
        queryClient.setQueryData(['userData', user?.uid], newUserData);
        
        toast({
            title: "Plan Activated!",
            description: "You're all set. Let's get started with your first workout.",
        });
        
        console.log("[ChoosePlanPage] Redirecting to /dashboard/today...");
        router.push('/dashboard/today');
    },
    onError: (error) => {
      console.error("[ChoosePlanPage] 🔴 Mutation FAILED:", error);
      toast({ variant: 'destructive', title: 'Error', description: 'Could not activate the selected plan. Please try again.' });
    }
  });

  const handleSelectPlan = (planId: string) => {
    setSelectedPlanId(planId);
  };
  
  const handleConfirmSelection = () => {
    if (!selectedPlanId || !user || !userData) {
        console.error("[ChoosePlanPage] 🔴 Cannot confirm: missing data.", { selectedPlanId, user, userData });
        return;
    }

    const updatedPlans = userData.plans.map(p => ({
        ...p,
        isActive: p.id === selectedPlanId
    }));
    
    const newUserData: UserData = {
        ...userData,
        plans: updatedPlans,
        onboardingStatus: 'completed'
    };
    
    mutation.mutate(newUserData);
  };

  if (isLoadingUserData) {
    return <LoadingSkeleton />;
  }
  
  const allPlans = userData?.plans || [];

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-background p-4">
        <div className="w-full max-w-3xl space-y-8">
            <div className="text-center">
                <h1 className="text-3xl font-bold text-primary">Choose Your Starting Plan</h1>
                <p className="text-muted-foreground mt-2">Select one of our pre-built plans to get started immediately. You can customize it later.</p>
            </div>

            <div className="space-y-4">
                 {allPlans.map(plan => (
                    <Card 
                        key={plan.id}
                        className={`cursor-pointer transition-all ${selectedPlanId === plan.id ? 'border-primary ring-2 ring-primary' : 'hover:border-primary/50'}`}
                        onClick={() => handleSelectPlan(plan.id)}
                    >
                        <CardHeader>
                            <CardTitle className="flex items-center justify-between">
                                {plan.name}
                                {selectedPlanId === plan.id && <CheckCircle className="h-6 w-6 text-primary" />}
                            </CardTitle>
                            {plan.description && <CardDescription>{plan.description}</CardDescription>}
                        </CardHeader>
                    </Card>
                 ))}
                 {allPlans.length === 0 && (
                     <Card>
                        <CardHeader>
                            <CardTitle>No Plans Available</CardTitle>
                            <CardDescription>Could not load default workout plans. Please try refreshing the page.</CardDescription>
                        </CardHeader>
                     </Card>
                 )}
            </div>
            
            <div className="text-center">
                <Button 
                    size="lg" 
                    onClick={handleConfirmSelection}
                    disabled={!selectedPlanId || mutation.isPending}
                >
                    {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Confirm and Start Workout
                </Button>
            </div>
        </div>
    </div>
  );
}
