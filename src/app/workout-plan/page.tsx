// src/app/workout-plan/page.tsx
'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { useUser } from '@/context/user-context';
import { setTodayWorkoutOverride as setOverrideService } from '@/lib/firestore-settings-service';
import type { WorkoutDay, Exercise, ExerciseLogData, UserData, NamedWorkoutPlan, SetData } from '../../types/workout';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ArrowRight, CalendarDays, Edit, Save, XCircle, PlusCircle, Trash2, ArrowUp, ArrowDown, Info, CheckCircle, WandSparkles, PlayCircle, Loader2, Dumbbell } from 'lucide-react';
import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { useToast } from '@/hooks/use-toast';
import AddExerciseModal from '@/components/workout-plan/add-exercise-modal';
import { produce } from 'immer';
import LoadingWorkoutPlanPage from './loading';
import { cn } from '@/lib/utils';


const daysOfWeekMap: { name: string, value: number }[] = [
  { name: "Unassigned", value: -1 },
  { name: "Sunday", value: 0 },
  { name: "Monday", value: 1 },
  { name: "Tuesday", value: 2 },
  { name: "Wednesday", value: 3 },
  { name: "Thursday", value: 4 },
  { name: "Friday", value: 5 },
  { name: "Saturday", value: 6 },
];

export default function WorkoutPlanPage() {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const router = useRouter();
  const { toast } = useToast();

  const [editableActivePlan, setEditableActivePlan] = useState<WorkoutDay[] | null>(null);
  const [isEditMode, setIsEditMode] = useState(false);

  const [isExerciseModalOpen, setIsExerciseModalOpen] = useState(false);
  const [dayIdForModal, setDayIdForModal] = useState<string | null>(null);
  const [exerciseToEdit, setExerciseToEdit] = useState<Exercise | null>(null);

  const { userData, isLoading: isLoadingUserData, updatePlan, setActivePlan } = useUser();



  const activePlanDetails = useMemo(() => userData?.plans.find((p: NamedWorkoutPlan) => p.isActive), [userData]);
  const allPlans = useMemo(() => userData?.plans, [userData]);

  useEffect(() => {
    if (activePlanDetails && !isEditMode) {
      const clonedPlan = JSON.parse(JSON.stringify(activePlanDetails.plan));
      setEditableActivePlan(clonedPlan);
    }
  }, [activePlanDetails, isEditMode]);

  const setOverrideMutation = useMutation({
    mutationFn: (dayId: string) => {
      if (!user) throw new Error("User not authenticated.");
      return setOverrideService(user.uid, dayId);
    },
    onSuccess: (data, dayId) => {
      queryClient.invalidateQueries({ queryKey: ['todayOverride', user?.uid] });
      toast({
        title: "Session Override Set",
        description: `Today's session is now '${editableActivePlan?.find(d => d.id === dayId)?.dayName}'. Go to 'Today's Session' to log.`,
      });
      router.push('/dashboard/today');
    }
  });

  const openExerciseModal = useCallback((dayId: string, exercise: Exercise | null) => {
    setDayIdForModal(dayId);
    setExerciseToEdit(exercise);
    setIsExerciseModalOpen(true);
  }, []);

  const handleSetPlanActive = useCallback(async (planId: string) => {
    try {
      await setActivePlan(planId);
      setIsEditMode(false);
      toast({ title: "Active Plan Switched", description: "The active workout plan has been updated." });
    } catch (error) {
      toast({ variant: 'destructive', title: "Error", description: "Could not switch plan." });
    }
  }, [setActivePlan, toast]);

  const handleSaveChangesToActivePlan = useCallback(async () => {
    if (activePlanDetails && editableActivePlan && userData) {
      const isCompletingOnboarding = userData.onboardingStatus === 'needs_plan_selection';

      try {
        await updatePlan(activePlanDetails.id, { plan: editableActivePlan });
        setIsEditMode(false);
        toast({ title: "Active Plan Updated", description: `Changes to '${activePlanDetails.name}' have been saved.` });
        if (isCompletingOnboarding) {
          router.push('/dashboard/today');
        }
      } catch (error) {
        toast({ variant: 'destructive', title: "Error", description: "Could not save changes." });
      }
    }
  }, [activePlanDetails, editableActivePlan, userData, updatePlan, toast, router]);

  const handleDayDetailChange = useCallback((dayId: string, field: keyof WorkoutDay, value: string | number | undefined) => {
    setEditableActivePlan(current => {
      if (!current) return null;
      return produce(current, (draft: WorkoutDay[]) => {
        const day = draft.find((d: WorkoutDay) => d.id === dayId);
        if (day) {
          if (field === 'mapsToActualDayOfWeek') {
            (day as any)[field] = value;
            const selectedDayObj = daysOfWeekMap.find(d => d.value === value);
            day.dayName = selectedDayObj && selectedDayObj.value !== -1 ? selectedDayObj.name : "Unassigned Day";
          } else {
            (day as any)[field] = value;
          }
        }
      });
    });
  }, []);

  const handleCancelChangesToActivePlan = useCallback(() => {
    if (activePlanDetails) {
      // Re-clone from the pristine source from query cache
      const originalPlan = userData?.plans.find((p: NamedWorkoutPlan) => p.id === activePlanDetails.id);
      if (originalPlan) {
        setEditableActivePlan(JSON.parse(JSON.stringify(originalPlan.plan)));
      }
    }
    setIsEditMode(false);
    toast({ title: "Changes Canceled", description: "Modifications to the active plan have been discarded." });
  }, [activePlanDetails, userData, toast]);

  const handleSaveExerciseToActivePlan = useCallback((dayId: string, savedExercise: Exercise) => {
    setEditableActivePlan(currentPlan => {
      if (!currentPlan) return null;
      return produce(currentPlan, (draft: WorkoutDay[]) => {
        const day = draft.find(d => d.id === dayId);
        if (day) {
          const existingExerciseIndex = day.exercises.findIndex(ex => ex.id === savedExercise.id);
          if (existingExerciseIndex !== -1) {
            day.exercises[existingExerciseIndex] = savedExercise;
          } else {
            day.exercises.push(savedExercise);
          }
        }
      });
    });
    setIsExerciseModalOpen(false);
    setDayIdForModal(null);
    setExerciseToEdit(null);
    toast({
      title: exerciseToEdit ? "Exercise Updated" : "Exercise Added",
      description: `${savedExercise.name} staged for changes. Save plan to apply.`
    });
  }, [exerciseToEdit, toast]);

  const getDisplayDayName = (day: WorkoutDay): string => {
    if (day.mapsToActualDayOfWeek !== undefined && day.mapsToActualDayOfWeek !== -1) {
      const mapped = daysOfWeekMap.find(d => d.value === day.mapsToActualDayOfWeek);
      return mapped ? mapped.name : day.dayName;
    }
    return day.dayName;
  };

  const handleAddDayToActivePlan = useCallback(() => {
    const newDayId = `custom-day-${Date.now()}`;
    const newDay: WorkoutDay = {
      id: newDayId,
      dayName: 'Unassigned Day',
      title: 'New Workout Focus',
      exercises: [],
      notes: 'Add exercises and notes for this day.',
      mapsToActualDayOfWeek: -1,
    };
    setEditableActivePlan(current => {
      if (!current) return [newDay];
      return produce(current, (draft: WorkoutDay[]) => { draft.push(newDay); });
    });
    toast({ title: "New Day Added", description: "Save plan changes when done." });
  }, []);

  const handleRemoveExerciseFromActivePlan = useCallback((dayId: string, exerciseId: string) => {
    setEditableActivePlan(current => {
      if (!current) return null;
      return produce(current, (draft: WorkoutDay[]) => {
        const day = draft.find((d) => d.id === dayId);
        if (day) {
          day.exercises = day.exercises.filter((ex: Exercise) => ex.id !== exerciseId);
        }
      });
    });
  }, []);

  const handleMoveExerciseInActivePlan = useCallback((dayId: string, exerciseId: string, direction: 'up' | 'down') => {
    setEditableActivePlan(current => {
      if (!current) return null;
      return produce(current, (draft: WorkoutDay[]) => {
        const day = draft.find((d) => d.id === dayId);
        if (day) {
          const index = day.exercises.findIndex((ex: Exercise) => ex.id === exerciseId);
          if (index === -1) return;
          if (direction === 'up' && index > 0) {
            [day.exercises[index], day.exercises[index - 1]] = [day.exercises[index - 1], day.exercises[index]];
          } else if (direction === 'down' && index < day.exercises.length - 1) {
            [day.exercises[index], day.exercises[index + 1]] = [day.exercises[index + 1], day.exercises[index]];
          }
        }
      });
    });
  }, []);

  if (isLoadingUserData) {
    return <LoadingWorkoutPlanPage />;
  }

  return (
    <div className="space-y-10 pb-20 animate-in fade-in duration-700">
      <header className="mb-8 flex flex-col md:flex-row justify-between items-start md:items-center gap-6">
        <div className="max-w-full">
          <h1 className="text-2xl md:text-3xl font-black text-primary flex items-center flex-wrap gap-2">
            <WandSparkles className="h-7 w-7 md:h-8 md:w-8" />
            <span className="tracking-tighter uppercase italic">Protocol Management</span>
          </h1>
          <p className="text-muted-foreground mt-2 text-xs md:text-sm font-medium opacity-60">
            Switch between workout regimes or architecturalize your active plan.
          </p>
        </div>
        <Button onClick={() => router.push('/onboarding/create-plan')} variant="outline" size="sm" className="w-full md:w-auto h-11 rounded-xl border-primary/20 text-primary hover:bg-primary/5 interactive-scale">
          <PlusCircle className="mr-2 h-4 w-4" /> Initialize New Plan
        </Button>
      </header>

      <section className="mb-12">
        <h2 className="text-[10px] font-black uppercase tracking-[0.2em] text-foreground/40 mb-4 px-1">Available Architectures</h2>
        {allPlans && allPlans.length > 0 ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {allPlans.map((plan: NamedWorkoutPlan) => (
              <Card key={plan.id} className={cn(
                "glass-panel border-none rounded-2xl transition-all duration-300",
                plan.isActive ? "ring-1 ring-primary shadow-lg shadow-primary/10" : "opacity-60 grayscale-[0.5]"
              )}>
                <CardHeader className="p-6">
                  <CardTitle className="text-lg font-black tracking-tight">{plan.name}</CardTitle>
                  {plan.description && <CardDescription className="text-xs font-medium italic opacity-50">{plan.description}</CardDescription>}
                </CardHeader>
                <CardFooter className="px-6 pb-6 pt-0">
                  <Button
                    onClick={() => handleSetPlanActive(plan.id)}
                    disabled={plan.isActive}
                    variant={plan.isActive ? "default" : "outline"}
                    size="sm"
                    className="w-full h-10 rounded-xl font-bold uppercase tracking-widest text-[10px]"
                  >
                    {plan.isActive ? <><CheckCircle className="mr-2 h-4 w-4" /> Current Protocol</> : "Activate"}
                  </Button>
                </CardFooter>
              </Card>
            ))}
          </div>
        ) : <p className="text-muted-foreground italic text-sm">No workout plans found.</p>}
      </section>

      <div className="h-[1px] w-full bg-white/5 my-12" />

      {activePlanDetails && editableActivePlan && (
        <section>
          <header className="mb-8 flex flex-col md:flex-row justify-between items-start md:items-center gap-6">
            <div className="max-w-full">
              <h2 className="text-xl md:text-2xl font-black text-primary flex items-center flex-wrap gap-3">
                <CalendarDays className="h-6 w-6 md:h-7 md:w-7" />
                <span className="tracking-tighter uppercase italic">{isEditMode ? "Optimizing: " : "Active: "} {activePlanDetails.name}</span>
              </h2>
              <p className="text-muted-foreground mt-2 text-xs md:text-sm font-medium opacity-60">
                {isEditMode ? "Fine-tune your weekly execution parameters." : "Browse your active protocol. Target a specific day to begin training."}
              </p>
            </div>
            <div className="flex flex-col sm:flex-row gap-2 w-full md:w-auto">
              {isEditMode ? (
                <>
                  <Button onClick={handleSaveChangesToActivePlan} variant="default" size="sm" className="h-11 rounded-xl bg-primary text-background flex-1 md:flex-none font-bold uppercase tracking-widest text-[10px] shadow-lg shadow-primary/20">
                    <Save className="mr-2 h-4 w-4" /> Commit Changes
                  </Button>
                  <Button onClick={handleCancelChangesToActivePlan} variant="outline" size="sm" className="h-11 rounded-xl border-white/10 hover:bg-white/5 flex-1 md:flex-none font-bold uppercase tracking-widest text-[10px]">
                    <XCircle className="mr-2 h-4 w-4" /> Discard
                  </Button>
                </>
              ) : (
                <Button onClick={() => setIsEditMode(true)} variant="outline" size="sm" className="h-11 rounded-xl border-white/10 hover:bg-white/5 w-full md:w-auto font-bold uppercase tracking-widest text-[10px]">
                  <Edit className="mr-2 h-4 w-4" /> Edit Architecture
                </Button>
              )}
            </div>
          </header>
          <div className="space-y-6">
            {editableActivePlan.map((day) => (
              <Card key={day.id} className="glass-panel border-none rounded-[2rem] overflow-hidden shadow-xl">
                <CardHeader className="p-6 md:p-8 bg-white/5">
                  {isEditMode ? (
                    <div className="space-y-4">
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div className="space-y-2">
                          <Label htmlFor={`${day.id}-mapsToActualDayOfWeek`} className="text-[9px] font-black uppercase tracking-widest opacity-40">Temporal Assignment</Label>
                          <Select
                            value={day.mapsToActualDayOfWeek !== undefined && day.mapsToActualDayOfWeek !== -1 ? String(day.mapsToActualDayOfWeek) : "-1"}
                            onValueChange={(value) => handleDayDetailChange(day.id, 'mapsToActualDayOfWeek', parseInt(value, 10))}
                          >
                            <SelectTrigger id={`${day.id}-mapsToActualDayOfWeek`} className="h-10 bg-white/5 border-white/10 rounded-xl font-bold">
                              <SelectValue placeholder="Select day" />
                            </SelectTrigger>
                            <SelectContent className="glass-panel border-white/10 rounded-xl">
                              {daysOfWeekMap.map(d => (
                                <SelectItem key={d.value} value={String(d.value)} className="hover:bg-primary/10">{d.name}</SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor={`${day.id}-title`} className="text-[9px] font-black uppercase tracking-widest opacity-40">Session Focus</Label>
                          <Input
                            id={`${day.id}-title`}
                            value={day.title}
                            onChange={(e) => handleDayDetailChange(day.id, 'title', e.target.value)}
                            className="h-10 bg-white/5 border-white/10 rounded-xl font-bold"
                          />
                        </div>
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor={`${day.id}-notes`} className="text-[9px] font-black uppercase tracking-widest opacity-40">Tactical Notes</Label>
                        <Input
                          id={`${day.id}-notes`}
                          value={day.notes || ''}
                          placeholder="Special instructions..."
                          onChange={(e) => handleDayDetailChange(day.id, 'notes', e.target.value)}
                          className="h-10 bg-white/5 border-white/10 rounded-xl font-medium italic"
                        />
                      </div>
                    </div>
                  ) : (
                    <div className="flex items-center justify-between gap-4">
                      <div>
                        <CardTitle className="text-xl font-black tracking-tight text-primary uppercase italic">{getDisplayDayName(day)}</CardTitle>
                        <CardDescription className="text-xs font-bold tracking-widest opacity-40 uppercase pt-1">{day.title}</CardDescription>
                      </div>
                      <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center border border-primary/20 shrink-0">
                        <CalendarDays className="h-5 w-5 text-primary" />
                      </div>
                    </div>
                  )}
                </CardHeader>
                <CardContent className="p-6 md:p-8 space-y-4">
                  {day.notes && !isEditMode && (
                    <div className="flex items-start gap-2 p-3 rounded-xl bg-white/5 border border-white/5 mb-4">
                      <Info className="h-3 w-3 text-primary mt-0.5 shrink-0" />
                      <p className="text-[10px] text-muted-foreground font-medium italic">{day.notes}</p>
                    </div>
                  )}
                  <div className="space-y-2">
                    {day.exercises.map((ex: Exercise, index: number) => (
                      <div key={ex.id} className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-3 rounded-xl bg-white/[0.02] border border-white/5 group hover:bg-white/5 transition-all">
                        <Link href={`/exercises/${ex.id}?planId=${activePlanDetails.id}&dayId=${day.id}`} className="flex items-center gap-3 flex-grow overflow-hidden">
                          <div className="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center shrink-0 group-hover:bg-primary/10 transition-colors">
                            <Dumbbell className="h-3.5 w-3.5 text-foreground/40 group-hover:text-primary transition-colors" />
                          </div>
                          <div className="overflow-hidden">
                            <p className="text-sm font-bold tracking-tight truncate shrink-0">{ex.name}</p>
                            <p className="text-[9px] font-black uppercase tracking-widest opacity-30 shrink-0">{ex.sets.length} VOLUMES</p>
                          </div>
                        </Link>

                        {isEditMode && (
                          <div className="flex items-center justify-end gap-1 shrink-0 pt-2 sm:pt-0 border-t sm:border-t-0 border-white/5">
                            <Button variant="ghost" size="icon" className="h-8 w-8 hover:bg-white/10" onClick={() => handleMoveExerciseInActivePlan(day.id, ex.id, 'up')} disabled={index === 0}>
                              <ArrowUp className="h-4 w-4" />
                            </Button>
                            <Button variant="ghost" size="icon" className="h-8 w-8 hover:bg-white/10" onClick={() => handleMoveExerciseInActivePlan(day.id, ex.id, 'down')} disabled={index === day.exercises.length - 1}>
                              <ArrowDown className="h-4 w-4" />
                            </Button>
                            <Button variant="ghost" size="icon" className="h-8 w-8 hover:bg-white/10 text-primary" onClick={() => openExerciseModal(day.id, ex)}>
                              <Edit className="h-4 w-4" />
                            </Button>
                            <Button variant="ghost" size="icon" className="h-8 w-8 hover:bg-destructive/10 text-destructive" onClick={() => handleRemoveExerciseFromActivePlan(day.id, ex.id)}>
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </div>
                        )}
                      </div>
                    ))}
                    {day.exercises.length === 0 && (
                      <div className="py-8 text-center bg-white/[0.02] border border-dashed border-white/10 rounded-2xl">
                        <p className="text-[10px] font-black uppercase tracking-widest opacity-20">No Movements Defined</p>
                      </div>
                    )}
                  </div>
                  {isEditMode && (
                    <Button variant="outline" size="sm" className="w-full h-12 rounded-xl border-dashed border-white/10 hover:bg-white/5 hover:border-primary/20 hover:text-primary transition-all interactive-scale mt-2" onClick={() => openExerciseModal(day.id, null)}>
                      <PlusCircle className="mr-2 h-4 w-4" /> Append Movement
                    </Button>
                  )}
                </CardContent>
                {!isEditMode && (
                  <CardFooter className="p-6 md:p-8 pt-0 flex flex-col sm:flex-row gap-3">
                    <Button asChild variant="ghost" className="flex-1 h-11 rounded-xl bg-white/5 border border-white/5 hover:bg-white/10 text-[10px] font-bold uppercase tracking-widest">
                      <Link href={`/workout/${day.id}`}>
                        Review Logistics <ArrowRight className="ml-2 h-3.5 w-3.5" />
                      </Link>
                    </Button>
                    <Button
                      variant="default"
                      className="flex-1 h-11 rounded-xl bg-primary text-background font-bold uppercase tracking-widest text-[10px] shadow-lg shadow-primary/20"
                      onClick={() => setOverrideMutation.mutate(day.id)}
                      disabled={!user || setOverrideMutation.isPending}
                    >
                      {setOverrideMutation.isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <PlayCircle className="mr-2 h-4 w-4" />} Initialize Session
                    </Button>
                  </CardFooter>
                )}
              </Card>
            ))}
            {isEditMode && (
              <Button variant="outline" onClick={handleAddDayToActivePlan} className="w-full h-16 rounded-[1.5rem] border-dashed border-white/10 hover:bg-primary/5 hover:border-primary/20 text-primary font-black uppercase tracking-widest text-xs transition-all interactive-scale mt-4">
                <PlusCircle className="mr-2 h-5 w-5" /> Architecturalize New Day
              </Button>
            )}
          </div>
        </section>
      )}

      {isExerciseModalOpen && dayIdForModal && (
        <AddExerciseModal
          isOpen={isExerciseModalOpen}
          onOpenChange={setIsExerciseModalOpen}
          onSave={(exercise) => {
            if (dayIdForModal) {
              handleSaveExerciseToActivePlan(dayIdForModal, exercise);
            }
          }}
          dayId={dayIdForModal!}
          initialData={exerciseToEdit}
        />
      )}
    </div>
  );
}
