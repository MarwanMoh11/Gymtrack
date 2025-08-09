
// src/app/onboarding/create-plan/add-exercises/page.tsx
'use client';

import { Suspense, useState, useMemo, useEffect } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { produce } from 'immer';

import type { WorkoutDay, Exercise, NamedWorkoutPlan, UserData, NewSetData } from '@/types/workout';
import { getUserData, saveUserData } from '@/lib/firestore-workout-plan-service';
import { getAllExercisesFromPlan as getAllExercisesForAutocompleteGlobal } from '@/data/workout-data';

import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { Loader2, PlusCircle, Trash2 } from 'lucide-react';
import AddExerciseModal from '@/components/workout-plan/add-exercise-modal';
import LoadingAddExercisesPage from './loading';

type ConfiguredDay = {
  dayName: string;
  title: string;
  mapsToActualDayOfWeek: number;
}

const daysOfWeekMap: { name: string, value: number }[] = [
  { name: "Unassigned", value: -1 }, { name: "Sunday", value: 0 }, { name: "Monday", value: 1 },
  { name: "Tuesday", value: 2 }, { name: "Wednesday", value: 3 },
  { name: "Thursday", value: 4 }, { name: "Friday", value: 5 },
  { name: "Saturday", value: 6 },
];

function AddExercisesComponent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const { toast } = useToast();

  const [workoutPlan, setWorkoutPlan] = useState<WorkoutDay[]>([]);
  const [isExerciseModalOpen, setIsExerciseModalOpen] = useState(false);
  const [dayIdForModal, setDayIdForModal] = useState<string | null>(null);
  
  const planDetails = useMemo(() => {
    const data = searchParams.get('data');
    if (!data) return null;
    try {
      return JSON.parse(decodeURIComponent(data));
    } catch {
      return null;
    }
  }, [searchParams]);

  const { data: userData, isLoading: isLoadingUser } = useQuery({
    queryKey: ['userData', user?.uid],
    queryFn: () => getUserData(user!.uid),
    enabled: !!user,
  });

  const { data: allExercises, isLoading: isLoadingAllExercises } = useQuery({
    queryKey: ['allExercisesForAutocomplete'],
    queryFn: getAllExercisesForAutocompleteGlobal,
  });

  const mutation = useMutation({
    mutationFn: (newUserData: UserData) => saveUserData(user!.uid, newUserData),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['userData', user?.uid] });
      toast({
        title: "Plan Created Successfully!",
        description: "Your new custom plan is now active.",
      });
      router.push('/dashboard/today');
    },
    onError: (e) => {
      toast({ variant: 'destructive', title: 'Error', description: `Could not save the new plan. ${(e as Error).message}` });
    }
  });

  useEffect(() => {
    if (planDetails && workoutPlan.length === 0) {
      const { configuredDays } = planDetails;
      const initialPlan = configuredDays.map((day: ConfiguredDay, index: number) => ({
        id: `custom-day-${Date.now()}-${index}`,
        dayName: daysOfWeekMap.find(d => d.value === day.mapsToActualDayOfWeek)?.name || `Day ${index + 1}`,
        title: day.title,
        exercises: [],
        notes: '',
        mapsToActualDayOfWeek: day.mapsToActualDayOfWeek,
      }));
      setWorkoutPlan(initialPlan);
    }
  }, [planDetails, workoutPlan.length]);

  const handleOpenExerciseModal = (dayId: string) => {
    setDayIdForModal(dayId);
    setIsExerciseModalOpen(true);
  };
  
  const handleSaveExercise = (exercise: Exercise) => {
    if (!dayIdForModal) return;
    setWorkoutPlan(
      produce(draft => {
        const day = draft.find(d => d.id === dayIdForModal);
        if (day) {
           const newExercise = { ...exercise, id: `custom-ex-${Date.now()}` };
           newExercise.sets = newExercise.sets.map((s, i) => ({...s, id: `set-${newExercise.id}-${i}`}));
           day.exercises.push(newExercise);
        }
      })
    );
    setIsExerciseModalOpen(false);
    setDayIdForModal(null);
  };

  const handleRemoveExercise = (dayId: string, exerciseId: string) => {
    setWorkoutPlan(produce(draft => {
      const day = draft.find(d => d.id === dayId);
      if (day) {
        day.exercises = day.exercises.filter(ex => ex.id !== exerciseId);
      }
    }));
  };

  const handleFinishPlan = () => {
    if (!userData || !planDetails) return;
    
    const newPlanId = `custom-plan-${planDetails.planName.trim().toLowerCase().replace(/\s+/g, '-')}-${Date.now()}`;
    
    const newPlan: NamedWorkoutPlan = {
      id: newPlanId,
      name: planDetails.planName,
      description: planDetails.planDescription,
      plan: workoutPlan.map(day => ({...day, exercises: day.exercises.map(ex => ({...ex, exerciseId: ex.id})) })), // Ensure exerciseId is set
      isActive: true,
    };
    
    const updatedOldPlans = userData.plans.map(p => ({ ...p, isActive: false }));
    const newUserData = { ...userData, plans: [...updatedOldPlans, newPlan], onboardingStatus: 'completed' as const };
    
    mutation.mutate(newUserData);
  };
  
  if (!planDetails || isLoadingUser || isLoadingAllExercises) {
    return <LoadingAddExercisesPage />;
  }
  
  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-background p-4">
      <Card className="w-full max-w-4xl">
        <CardHeader>
          <CardTitle className="text-2xl font-bold text-primary">Build Your Own Plan: Step 3 (Final)</CardTitle>
          <CardDescription>Add exercises to each day of your new plan: "{planDetails.planName}".</CardDescription>
        </CardHeader>
        <CardContent className="max-h-[60vh] overflow-y-auto p-4">
          <Accordion type="single" collapsible defaultValue={workoutPlan[0]?.id} className="w-full space-y-4">
            {workoutPlan.map(day => (
              <AccordionItem key={day.id} value={day.id} className="border rounded-lg bg-card/50 px-4">
                <AccordionTrigger className="hover:no-underline">
                    <div className="text-left">
                        <h3 className="font-semibold text-lg text-secondary-foreground">{day.dayName}</h3>
                        <p className="text-sm text-muted-foreground">{day.title}</p>
                    </div>
                </AccordionTrigger>
                <AccordionContent>
                  <ul className="space-y-2 mt-2">
                    {day.exercises.map(ex => (
                      <li key={ex.id} className="flex justify-between items-center bg-secondary/30 p-2 rounded-md">
                        <span className="text-sm">{ex.name} ({ex.sets.length} sets)</span>
                        <Button variant="ghost" size="icon" className="h-7 w-7 text-destructive" onClick={() => handleRemoveExercise(day.id, ex.id)}>
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </li>
                    ))}
                    {day.exercises.length === 0 && (
                      <p className="text-sm text-muted-foreground italic text-center py-2">No exercises added yet.</p>
                    )}
                  </ul>
                  <Button variant="outline" size="sm" className="w-full mt-4" onClick={() => handleOpenExerciseModal(day.id)}>
                    <PlusCircle className="mr-2 h-4 w-4" /> Add Exercise
                  </Button>
                </AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </CardContent>
        <CardFooter className="flex justify-end pt-6">
          <Button onClick={handleFinishPlan} disabled={mutation.isPending}>
            {mutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Finish & Save Plan
          </Button>
        </CardFooter>
      </Card>
      
      {isExerciseModalOpen && allExercises && dayIdForModal && (
        <AddExerciseModal
            isOpen={isExerciseModalOpen}
            onOpenChange={setIsExerciseModalOpen}
            onSave={handleSaveExercise}
            allExercises={allExercises}
            dayId={dayIdForModal}
        />
      )}
    </div>
  );
}

export default function AddExercisesPage() {
    return (
        <Suspense fallback={<LoadingAddExercisesPage />}>
            <AddExercisesComponent />
        </Suspense>
    )
}
