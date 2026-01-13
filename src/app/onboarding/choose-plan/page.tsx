// src/app/onboarding/choose-plan/page.tsx
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { getUserData, saveUserData } from '@/lib/firestore-workout-plan-service';
import type { NamedWorkoutPlan, UserData } from '../../../types/workout';
import { Card, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { CheckCircle, Loader2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { Skeleton } from '@/components/ui/skeleton';
import { cn } from '@/lib/utils';

function LoadingSkeleton() {
    return (
        <div className="flex flex-col items-center justify-center min-h-screen premium-gradient-bg p-4">
            <div className="w-full max-w-3xl space-y-8 animate-pulse">
                <div className="text-center space-y-4">
                    <Skeleton className="h-12 w-3/4 mx-auto rounded-2xl bg-white/5" />
                    <Skeleton className="h-6 w-1/2 mx-auto rounded-xl bg-white/5" />
                </div>
                <div className="space-y-4">
                    {[...Array(3)].map((_, i) => (
                        <div key={i} className="glass-panel h-32 rounded-[2rem] border-none" />
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
        queryFn: () => {
            if (!user) throw new Error("User not authenticated");
            return getUserData(user.uid);
        },
        enabled: !!user,
        staleTime: 1000 * 60 * 5,
    });

    const mutation = useMutation({
        mutationFn: (newUserData: UserData) => {
            if (!user) throw new Error("User not authenticated for mutation");
            return saveUserData(user.uid, newUserData);
        },
        onSuccess: (data, newUserData) => {
            queryClient.setQueryData(['userData', user?.uid], newUserData);
            toast({
                title: "Plan Activated!",
                description: "You're all set. Let's get started with your first workout.",
            });
            router.push('/dashboard/today');
        },
        onError: (error) => {
            toast({ variant: 'destructive', title: 'Error', description: 'Could not activate the selected plan. Please try again.' });
        }
    });

    const handleSelectPlan = (planId: string) => {
        setSelectedPlanId(planId);
    };

    const handleConfirmSelection = () => {
        if (!selectedPlanId || !user || !userData) {
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
        <div className="flex flex-col items-center justify-center min-h-screen premium-gradient-bg px-6 py-12">
            <div className="w-full max-w-2xl space-y-12">
                <div className="text-center animate-in fade-in slide-in-from-top-4 duration-700">
                    <h1 className="text-4xl md:text-5xl font-bold tracking-tight mb-4 font-heading">
                        Pick Your <span className="text-primary">Journey</span>
                    </h1>
                    <p className="text-muted-foreground text-lg uppercase tracking-widest text-[10px] font-semibold opacity-70">
                        Select a starting template to begin
                    </p>
                </div>

                <div className="space-y-4 animate-in fade-in slide-in-from-bottom-8 duration-1000 delay-200 fill-mode-both">
                    {allPlans.map((plan, index) => (
                        <div
                            key={plan.id}
                            className={cn(
                                "glass-panel border-none p-6 rounded-[2rem] cursor-pointer transition-all duration-300 relative overflow-hidden group interactive-scale",
                                selectedPlanId === plan.id ? "bg-white/10 ring-2 ring-primary" : "hover:bg-white/5"
                            )}
                            onClick={() => handleSelectPlan(plan.id)}
                            style={{ animationDelay: `${index * 100}ms` }}
                        >
                            <div className="flex items-center justify-between relative z-10">
                                <div className="space-y-1">
                                    <h3 className="text-xl font-bold">{plan.name}</h3>
                                    {plan.description && (
                                        <p className="text-sm text-muted-foreground line-clamp-2 max-w-[80%]">
                                            {plan.description}
                                        </p>
                                    )}
                                </div>
                                <div className={cn(
                                    "w-8 h-8 rounded-full border-2 flex items-center justify-center transition-all duration-300",
                                    selectedPlanId === plan.id ? "bg-primary border-primary" : "border-white/10 group-hover:border-primary/50"
                                )}>
                                    {selectedPlanId === plan.id && <CheckCircle className="h-5 w-5 text-background" />}
                                </div>
                            </div>

                            {/* Decorative background element */}
                            <div className={cn(
                                "absolute -right-4 -bottom-4 w-32 h-32 bg-primary/5 rounded-full blur-2xl transition-all duration-500",
                                selectedPlanId === plan.id ? "opacity-100 scale-110" : "opacity-0 scale-90"
                            )} />
                        </div>
                    ))}

                    {allPlans.length === 0 && (
                        <div className="glass-panel border-none p-12 rounded-[2rem] text-center">
                            <p className="text-muted-foreground italic">No plans found. Please refresh the page.</p>
                        </div>
                    )}
                </div>
            </div>

            {/* Floating action button area */}
            <div className="fixed bottom-0 left-0 right-0 p-8 glass-panel border-t border-glass-border flex justify-center z-50 animate-in slide-in-from-bottom-full duration-700 delay-500 fill-mode-both">
                <Button
                    size="lg"
                    className="w-full max-w-sm h-14 rounded-2xl bg-primary hover:bg-primary/90 text-sm font-bold uppercase tracking-widest shadow-2xl shadow-primary/20 interactive-scale"
                    onClick={handleConfirmSelection}
                    disabled={!selectedPlanId || mutation.isPending}
                >
                    {mutation.isPending ? <Loader2 className="h-6 w-6 animate-spin" /> : "Confirm & Start Your Workout"}
                </Button>
            </div>
        </div>
    );
}
