// src/app/onboarding/create-plan/add-exercises/page.tsx
'use client';

import React, { Suspense, useState, useMemo, useCallback } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { produce } from 'immer';

import type { WorkoutDay, Exercise, NamedWorkoutPlan, UserData, NewSetData, ExerciseLogData, SetData } from '../../../../types/workout';
import { getUserData, saveUserData } from '@/lib/firestore-workout-plan-service';

import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { Loader2, PlusCircle, Trash2, ArrowUp, ArrowDown, Edit, CheckCircle, Sparkles } from 'lucide-react';
import { cn } from '@/lib/utils';
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
  const [exerciseToEdit, setExerciseToEdit] = useState<Exercise | null>(null);

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



  const mutation = useMutation({
    mutationFn: (newUserData: UserData) => saveUserData(user!.uid, newUserData),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['userData', user?.uid] });
      toast({
        title: "Empire Built",
        description: "Your training protocol is now active.",
      });
      router.push('/dashboard/today');
    },
    onError: (e) => {
      toast({ variant: 'destructive', title: 'Error', description: `Could not save the new plan. ${(e as Error).message}` });
    }
  });

  React.useEffect(() => {
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

  const handleOpenExerciseModal = useCallback((dayId: string, exercise: Exercise | null) => {
    setDayIdForModal(dayId);
    setExerciseToEdit(exercise);
    setIsExerciseModalOpen(true);
  }, []);

  const handleSaveExercise = useCallback((savedExercise: Exercise) => {
    if (!dayIdForModal) {
      return;
    }
    setWorkoutPlan(
      produce((draft: WorkoutDay[]) => {
        const day = draft.find((d: WorkoutDay) => d.id === dayIdForModal);
        if (day) {
          const existingIndex = day.exercises.findIndex((ex: Exercise) => ex.id === savedExercise.id);
          if (existingIndex !== -1) {
            day.exercises[existingIndex] = savedExercise;
          } else {
            const newExerciseId = `custom-ex-${Date.now()}`;
            const newExercise = { ...savedExercise, id: newExerciseId };
            newExercise.sets = (newExercise.sets as any[]).map((s: any, i: number) => ({
              ...s,
              id: `set-${newExerciseId}-${i}`,
              exerciseId: newExerciseId,
              targetWeight: s.targetWeight || ''
            })) as SetData[];
            day.exercises.push(newExercise);
          }
        }
      })
    );
    setIsExerciseModalOpen(false);
    setDayIdForModal(null);
    setExerciseToEdit(null);
    toast({
      title: exerciseToEdit ? "Exercise Optimized" : "Exercise Enrolled",
      description: `${savedExercise.name} added to session.`
    })
  }, [dayIdForModal, exerciseToEdit, toast]);

  const handleRemoveExercise = (dayId: string, exerciseId: string) => {
    setWorkoutPlan(produce((draft: WorkoutDay[]) => {
      const day = draft.find((d: WorkoutDay) => d.id === dayId);
      if (day) {
        day.exercises = day.exercises.filter((ex: Exercise) => ex.id !== exerciseId);
      }
    }));
  };

  const handleMoveExercise = (dayId: string, exerciseId: string, direction: 'up' | 'down') => {
    setWorkoutPlan(produce((draft: WorkoutDay[]) => {
      const day = draft.find((d: WorkoutDay) => d.id === dayId);
      if (day) {
        const index = day.exercises.findIndex((ex: Exercise) => ex.id === exerciseId);
        if (index === -1) return;
        if (direction === 'up' && index > 0) {
          [day.exercises[index], day.exercises[index - 1]] = [day.exercises[index - 1], day.exercises[index]];
        } else if (direction === 'down' && index < day.exercises.length - 1) {
          [day.exercises[index], day.exercises[index + 1]] = [day.exercises[index + 1], day.exercises[index]];
        }
      }
    }));
  };

  const handleFinishPlan = () => {
    if (!userData || !planDetails) {
      return;
    }

    const newPlanId = `custom-plan-${planDetails.planName.trim().toLowerCase().replace(/\s+/g, '-')}-${Date.now()}`;

    const newPlan: NamedWorkoutPlan = {
      id: newPlanId,
      name: planDetails.planName,
      description: planDetails.planDescription,
      plan: workoutPlan,
      isActive: true,
    };


    const updatedOldPlans = userData.plans.map((p: NamedWorkoutPlan) => ({ ...p, isActive: false }));
    const newUserData = { ...userData, plans: [...updatedOldPlans, newPlan], onboardingStatus: 'completed' as const };

    mutation.mutate(newUserData);
  };

  if (!planDetails || isLoadingUser) {
    return <LoadingAddExercisesPage />;
  }

  return (
    <div className="flex flex-col items-center justify-start min-h-screen premium-gradient-bg px-6 py-16">
      <div className="w-full max-w-4xl mb-12 animate-in fade-in slide-in-from-top-4 duration-700">
        <div className="flex items-center gap-4 mb-8 max-w-2xl mx-auto">
          <div className="w-10 h-10 rounded-full bg-primary flex items-center justify-center border border-primary text-background font-bold shadow-lg shadow-primary/20">
            <CheckCircle className="h-6 w-6" />
          </div>
          <div className="flex-1 h-[2px] bg-primary rounded-full relative overflow-hidden">
            <div className="absolute inset-0 bg-primary w-full animate-in slide-in-from-left duration-1000" />
          </div>
          <div className="w-10 h-10 rounded-full bg-primary flex items-center justify-center border border-primary text-background font-bold shadow-lg shadow-primary/20">
            <CheckCircle className="h-6 w-6" />
          </div>
          <div className="flex-1 h-[2px] bg-primary/30 rounded-full relative overflow-hidden">
            <div className="absolute inset-0 bg-primary w-full animate-in slide-in-from-left duration-1000" />
          </div>
          <div className="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center border border-primary/30 text-primary font-bold shadow-lg shadow-primary/10">3</div>
        </div>

        <div className="text-center">
          <h1 className="text-4xl md:text-5xl font-bold tracking-tight mb-4 font-heading">
            Populate Your <span className="text-primary">Sessions</span>
          </h1>
          <p className="text-muted-foreground text-lg uppercase tracking-widest text-[10px] font-semibold opacity-70">
            Phase 3: The Workload
          </p>
        </div>
      </div>

      <div className="w-full max-w-4xl space-y-8 mb-40 animate-in fade-in slide-in-from-bottom-8 duration-1000 delay-200 fill-mode-both">
        <Accordion type="single" collapsible defaultValue={workoutPlan[0]?.id} className="space-y-6">
          {workoutPlan.map((day, dayIndex) => (
            <AccordionItem
              key={day.id}
              value={day.id}
              className="glass-panel border-none rounded-[2.5rem] px-8 overflow-hidden group transition-all duration-300 data-[state=open]:bg-white/10"
            >
              <AccordionTrigger className="hover:no-underline py-8">
                <div className="flex items-center gap-6 text-left">
                  <div className="w-14 h-14 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center group-hover:bg-primary/20 transition-colors duration-300">
                    <span className="text-primary font-bold text-lg">{dayIndex + 1}</span>
                  </div>
                  <div>
                    <h3 className="font-bold text-xl font-heading tracking-tight">{day.dayName}</h3>
                    <p className="text-muted-foreground opacity-70 font-medium uppercase tracking-widest text-[10px]">
                      {day.title || "No Focus Set"}
                    </p>
                  </div>
                </div>
              </AccordionTrigger>
              <AccordionContent className="pb-8">
                <div className="space-y-4">
                  {day.exercises.map((ex: Exercise, index: number) => (
                    <div
                      key={ex.id}
                      className="flex justify-between items-center bg-white/5 hover:bg-white/10 p-5 rounded-2xl transition-all duration-200 group/item border border-white/5 hover:border-white/10"
                    >
                      <div className="flex items-center gap-4">
                        <div className="w-2 h-8 bg-primary/20 rounded-full" />
                        <div>
                          <p className="font-bold text-lg">{ex.name}</p>
                          <p className="text-xs text-muted-foreground font-medium uppercase tracking-tighter opacity-70">
                            {ex.sets.length} Premium Sets • {ex.unit === 'reps' ? 'Bodyweight / Weighted' : 'Duration'}
                          </p>
                        </div>
                      </div>
                      <div className="flex gap-2 items-center opacity-0 group-hover/item:opacity-100 transition-opacity">
                        <Button variant="ghost" size="icon" className="h-9 w-9 rounded-xl bg-white/5 hover:bg-white/20" onClick={() => handleMoveExercise(day.id, ex.id, 'up')} disabled={index === 0}>
                          <ArrowUp className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" className="h-9 w-9 rounded-xl bg-white/5 hover:bg-white/20" onClick={() => handleMoveExercise(day.id, ex.id, 'down')} disabled={index === day.exercises.length - 1}>
                          <ArrowDown className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" className="h-9 w-9 rounded-xl bg-white/5 hover:bg-white/20 text-primary" onClick={() => handleOpenExerciseModal(day.id, ex)}>
                          <Edit className="h-4 w-4" />
                        </Button>
                        <Button variant="ghost" size="icon" className="h-9 w-9 rounded-xl bg-white/5 hover:bg-destructive/10 text-destructive" onClick={() => handleRemoveExercise(day.id, ex.id)}>
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </div>
                  ))}

                  {day.exercises.length === 0 && (
                    <div className="py-12 text-center rounded-3xl border border-dashed border-white/10 bg-white/[0.02]">
                      <p className="text-muted-foreground italic text-sm">No exercises staged for this session.</p>
                    </div>
                  )}

                  <Button
                    variant="outline"
                    className="w-full h-14 mt-4 rounded-2xl border-white/10 hover:bg-white/5 bg-transparent group/add interactive-scale"
                    onClick={() => handleOpenExerciseModal(day.id, null)}
                  >
                    <PlusCircle className="mr-2 h-5 w-5 text-primary group-hover/add:scale-110 transition-transform" />
                    <span className="font-bold uppercase tracking-widest text-xs">Add Exercise</span>
                  </Button>
                </div>
              </AccordionContent>
            </AccordionItem>
          ))}
        </Accordion>
      </div>

      {/* Floating action button area */}
      <div className="fixed bottom-0 left-0 right-0 p-8 glass-panel border-t border-glass-border flex justify-center z-50 animate-in slide-in-from-bottom-full duration-700 delay-500 fill-mode-both">
        <Button
          onClick={handleFinishPlan}
          disabled={mutation.isPending}
          className="w-full max-w-sm h-14 rounded-2xl bg-primary hover:bg-primary/90 text-sm font-bold uppercase tracking-widest shadow-2xl shadow-primary/20 interactive-scale"
        >
          {mutation.isPending ? <Loader2 className="h-6 w-6 animate-spin" /> : "Deploy Training Protocol"}
        </Button>
      </div>

      <AddExerciseModal
        isOpen={isExerciseModalOpen}
        onOpenChange={setIsExerciseModalOpen}
        onSave={handleSaveExercise}
        dayId={dayIdForModal}
        initialData={exerciseToEdit}
      />
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
