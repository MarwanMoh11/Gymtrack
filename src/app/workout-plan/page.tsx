// src/app/workout-plan/page.tsx
'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useAuth } from '@/context/auth-context';
import { getUserData, saveUserData } from '@/lib/firestore-workout-plan-service';
import { setTodayWorkoutOverride as setOverrideService } from '@/lib/firestore-settings-service';
import type { WorkoutDay, Exercise, NamedWorkoutPlan, UserData } from '@/types/workout';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ArrowRight, CalendarDays, Edit, Save, XCircle, PlusCircle, Trash2, ArrowUp, ArrowDown, Info, CheckCircle, WandSparkles, PlayCircle, Loader2 } from 'lucide-react';
import React, { useState, useEffect, useMemo } from 'react';
import { useToast } from '@/hooks/use-toast';
import AddExerciseModal from '@/components/workout-plan/add-exercise-modal';
import { getAllExercisesFromPlan as getAllExercisesForAutocompleteGlobal } from '@/data/workout-data';
import { produce } from 'immer';
import LoadingWorkoutPlanPage from './loading';

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
  const [initialActivePlanForEdit, setInitialActivePlanForEdit] = useState<WorkoutDay[] | null>(null);
  const [isEditMode, setIsEditMode] = useState(false);
  const [isExerciseModalOpen, setIsExerciseModalOpen] = useState(false);
  const [dayIdForModal, setDayIdForModal] = useState<string | null>(null);
  const [exerciseToEdit, setExerciseToEdit] = useState<Exercise | null>(null);
  const [isNewPlanDialogVisible, setIsNewPlanDialogVisible] = useState(false);
  const [newPlanNameInput, setNewPlanNameInput] = useState('');
  
  const { data: userData, isLoading: isLoadingUserData } = useQuery({
    queryKey: ['userData', user?.uid],
    queryFn: () => getUserData(user!.uid),
    enabled: !!user,
  });

  const { data: allExercisesForModal, isLoading: isLoadingAllExercises } = useQuery({
      queryKey: ['allExercisesForAutocomplete'],
      queryFn: getAllExercisesForAutocompleteGlobal,
  });

  const activePlanDetails = useMemo(() => userData?.plans.find(p => p.isActive), [userData]);
  const allPlans = useMemo(() => userData?.plans, [userData]);

  useEffect(() => {
    if (activePlanDetails && !isEditMode) {
      const clonedPlan = JSON.parse(JSON.stringify(activePlanDetails.plan));
      setEditableActivePlan(clonedPlan);
      setInitialActivePlanForEdit(clonedPlan);
    }
  }, [activePlanDetails, isEditMode]);

  const saveUserDataMutation = useMutation({
    mutationFn: (newUserData: UserData) => saveUserData(user!.uid, newUserData),
    onSuccess: (data, newUserData) => {
        queryClient.setQueryData(['userData', user?.uid], newUserData);
    },
    onError: (error) => {
      toast({ variant: 'destructive', title: 'Error', description: `Could not save changes. ${error.message}` });
    }
  });

  const setOverrideMutation = useMutation({
    mutationFn: (dayId: string) => {
      if (!user) throw new Error("User not authenticated.");
      return setOverrideService(user.uid, dayId);
    },
    onSuccess: (data, dayId) => {
      queryClient.invalidateQueries({ queryKey: ['todayOverride', user?.uid]});
      toast({
        title: "Session Override Set",
        description: `Today's session is now '${editableActivePlan?.find(d => d.id === dayId)?.dayName}'. Go to 'Today's Session' to log.`,
      });
      router.push('/dashboard/today');
    }
  });

  const handleSetPlanActive = (planId: string) => {
    if (!userData) return;
    const updatedPlans = userData.plans.map(p => ({ ...p, isActive: p.id === planId }));
    saveUserDataMutation.mutate({ ...userData, plans: updatedPlans });
    setIsEditMode(false);
    toast({ title: "Active Plan Switched", description: "The active workout plan has been updated." });
  };
  
  const handleSaveChangesToActivePlan = () => {
    if (activePlanDetails && editableActivePlan && userData) {
      const updatedPlans = userData.plans.map(p => p.id === activePlanDetails.id ? { ...p, plan: editableActivePlan } : p);
      saveUserDataMutation.mutate(
        { ...userData, plans: updatedPlans },
        {
          onSuccess: () => {
             setInitialActivePlanForEdit(JSON.parse(JSON.stringify(editableActivePlan)));
             setIsEditMode(false);
             toast({ title: "Active Plan Updated", description: `Changes to '${activePlanDetails.name}' have been saved.` });
          }
      });
    }
  };

  const handleActualCreateNewPlan = () => {
    if (!newPlanNameInput.trim() || !userData) {
      toast({ variant: 'destructive', title: 'Plan Name Required', description: 'Please enter a name for the new plan.' });
      return;
    }
    const newPlanId = `custom-plan-${newPlanNameInput.trim().toLowerCase().replace(/\s+/g, '-')}-${Date.now()}`;
    const newPlan: NamedWorkoutPlan = {
      id: newPlanId,
      name: newPlanNameInput.trim(),
      description: "A new custom workout plan.",
      plan: [],
      isActive: false,
    };
    const newUserData = { ...userData, plans: [...userData.plans, newPlan] };
    saveUserDataMutation.mutate(newUserData, {
        onSuccess: () => {
            toast({ title: "New Plan Created", description: `Plan '${newPlan.name}' added.` });
            setIsNewPlanDialogVisible(false);
            setNewPlanNameInput('');
        }
    });
  };

  const handleDayDetailChange = (dayId: string, field: keyof WorkoutDay, value: string | number | undefined) => {
    if (!editableActivePlan) return;
    setEditableActivePlan(
      produce(editableActivePlan, draft => {
        const day = draft.find(d => d.id === dayId);
        if (day) {
          if (field === 'mapsToActualDayOfWeek') {
            (day as any)[field] = value;
            const selectedDayObj = daysOfWeekMap.find(d => d.value === value);
            day.dayName = selectedDayObj && selectedDayObj.value !== -1 ? selectedDayObj.name : "Unassigned Day";
          } else {
            (day as any)[field] = value;
          }
        }
      })
    );
  };
  
  const handleCancelChangesToActivePlan = () => {
    setEditableActivePlan(JSON.parse(JSON.stringify(initialActivePlanForEdit)));
    setIsEditMode(false);
    toast({ title: "Changes Canceled", description: "Modifications to the active plan have been discarded." });
  };
  
  const handleSaveExerciseToActivePlan = (dayId: string, savedExercise: Exercise) => {
     if (!editableActivePlan) return;
     setEditableActivePlan(
      produce(editableActivePlan, draft => {
        const day = draft.find(d => d.id === dayId);
        if (day) {
          const existingExerciseIndex = day.exercises.findIndex(ex => ex.id === savedExercise.id);
          if (existingExerciseIndex !== -1) { 
            day.exercises[existingExerciseIndex] = savedExercise;
          } else { 
            day.exercises.push(savedExercise);
          }
        }
      })
    );
    setIsExerciseModalOpen(false);
    setDayIdForModal(null);
    setExerciseToEdit(null);
    toast({ 
      title: exerciseToEdit ? "Exercise Updated" : "Exercise Added", 
      description: `${savedExercise.name} staged for changes. Save plan to apply.`
    });
  };

  const getDisplayDayName = (day: WorkoutDay): string => {
    if (day.mapsToActualDayOfWeek !== undefined && day.mapsToActualDayOfWeek !== -1) {
      const mapped = daysOfWeekMap.find(d => d.value === day.mapsToActualDayOfWeek);
      return mapped ? mapped.name : day.dayName;
    }
    return day.dayName;
  };

  const handleAddDayToActivePlan = () => {
    if (!editableActivePlan) return;
    const newDayId = `custom-day-${Date.now()}`;
    const newDay: WorkoutDay = {
      id: newDayId,
      dayName: 'Unassigned Day', 
      title: 'New Workout Focus',
      exercises: [],
      notes: 'Add exercises and notes for this day.',
      mapsToActualDayOfWeek: -1, 
    };
    setEditableActivePlan(produce(editableActivePlan, draft => { draft.push(newDay); }));
    toast({ title: "New Day Added", description: "Save plan changes when done." });
  };
  
  const handleRemoveExerciseFromActivePlan = (dayId: string, exerciseId: string) => {
    if (!editableActivePlan) return;
    setEditableActivePlan(
      produce(editableActivePlan, draft => {
        const day = draft.find(d => d.id === dayId);
        if (day) {
          day.exercises = day.exercises.filter(ex => ex.id !== exerciseId);
        }
      })
    );
  };
  
  const handleMoveExerciseInActivePlan = (dayId: string, exerciseId: string, direction: 'up' | 'down') => {
    if (!editableActivePlan) return;
    setEditableActivePlan(
      produce(editableActivePlan, draft => {
        const day = draft.find(d => d.id === dayId);
        if (day) {
          const index = day.exercises.findIndex(ex => ex.id === exerciseId);
          if (index === -1) return;
          if (direction === 'up' && index > 0) {
            [day.exercises[index], day.exercises[index - 1]] = [day.exercises[index - 1], day.exercises[index]];
          } else if (direction === 'down' && index < day.exercises.length - 1) {
            [day.exercises[index], day.exercises[index + 1]] = [day.exercises[index + 1], day.exercises[index]];
          }
        }
      })
    );
  };

  const openExerciseModal = (dayId: string, exercise?: Exercise) => {
    setDayIdForModal(dayId);
    setExerciseToEdit(exercise || null);
    setIsExerciseModalOpen(true);
  };
  
  if (isLoadingUserData || isLoadingAllExercises) {
    return <LoadingWorkoutPlanPage />;
  }

  return (
    <div className="container mx-auto py-8 px-4 md:px-6">
      <header className="mb-8 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold text-primary flex items-center">
            <WandSparkles className="mr-3 h-8 w-8" />
            Manage Workout Plans
          </h1>
          <p className="text-muted-foreground mt-1">
            Switch between workout plans or customize the active one.
          </p>
        </div>
        <Button onClick={() => setIsNewPlanDialogVisible(true)} variant="outline" size="sm">
          <PlusCircle className="mr-2 h-4 w-4" /> Create New Plan
        </Button>
      </header>

      <section className="mb-12">
        <h2 className="text-2xl font-semibold mb-4 text-secondary-foreground">Available Plans</h2>
        {allPlans && allPlans.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {allPlans.map(plan => (
              <Card key={plan.id} className={`shadow-md ${plan.isActive ? 'border-primary ring-2 ring-primary' : 'border-border'}`}>
                <CardHeader>
                  <CardTitle className="text-lg">{plan.name}</CardTitle>
                  {plan.description && <CardDescription className="text-xs">{plan.description}</CardDescription>}
                </CardHeader>
                <CardFooter>
                  <Button 
                    onClick={() => handleSetPlanActive(plan.id)} 
                    disabled={plan.isActive || saveUserDataMutation.isPending}
                    variant={plan.isActive ? "default" : "outline"}
                    size="sm"
                    className="w-full"
                  >
                    {plan.isActive ? <><CheckCircle className="mr-2 h-4 w-4" /> Active Plan</> : "Set as Active"}
                  </Button>
                </CardFooter>
              </Card>
            ))}
          </div>
        ) : <p className="text-muted-foreground">No workout plans found.</p> }
      </section>
      
      <Separator className="my-8" />

      {activePlanDetails && editableActivePlan && (
        <section>
            <header className="mb-6 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
                <div>
                <h2 className="text-2xl font-semibold text-primary flex items-center">
                    <CalendarDays className="mr-3 h-7 w-7" />
                    {isEditMode ? "Editing: " : "Active Plan: "} {activePlanDetails.name}
                </h2>
                <p className="text-muted-foreground mt-1">
                    {isEditMode ? "Customize your weekly schedule for the active plan." : "Browse the active workout plan. Click 'Start Session' to log a specific day."}
                </p>
                </div>
                <div className="flex gap-2">
                {isEditMode ? (
                    <>
                    <Button onClick={handleSaveChangesToActivePlan} variant="default" size="sm" disabled={saveUserDataMutation.isPending}>
                        {saveUserDataMutation.isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin"/> : <Save className="mr-2 h-4 w-4" />} Save Changes
                    </Button>
                    <Button onClick={handleCancelChangesToActivePlan} variant="outline" size="sm" disabled={saveUserDataMutation.isPending}>
                        <XCircle className="mr-2 h-4 w-4" /> Cancel
                    </Button>
                    </>
                ) : (
                    <Button onClick={() => setIsEditMode(true)} variant="outline" size="sm">
                    <Edit className="mr-2 h-4 w-4" /> Edit Active Plan
                    </Button>
                )}
                </div>
            </header>
            <div className="space-y-8">
            {editableActivePlan.map((day) => (
                <Card key={day.id} className="shadow-lg rounded-2xl flex flex-col">
                <CardHeader>
                    {isEditMode ? (
                    <div className="space-y-3">
                        <div>
                            <Label htmlFor={`${day.id}-mapsToActualDayOfWeek`} className="text-xs font-medium text-muted-foreground">Assign to Day of Week</Label>
                            <Select
                              value={day.mapsToActualDayOfWeek !== undefined && day.mapsToActualDayOfWeek !== -1 ? String(day.mapsToActualDayOfWeek) : "-1"}
                              onValueChange={(value) => handleDayDetailChange(day.id, 'mapsToActualDayOfWeek', parseInt(value, 10))}
                            >
                              <SelectTrigger id={`${day.id}-mapsToActualDayOfWeek`} className="text-xl font-semibold text-primary h-9">
                                <SelectValue placeholder="Select day of week" />
                              </SelectTrigger>
                              <SelectContent>
                                {daysOfWeekMap.map(d => (
                                  <SelectItem key={d.value} value={String(d.value)}>{d.name}</SelectItem>
                                ))}
                              </SelectContent>
                            </Select>
                          </div>
                        <div>
                        <Label htmlFor={`${day.id}-title`} className="text-xs font-medium text-muted-foreground">Day Title/Focus</Label>
                        <Input
                            id={`${day.id}-title`}
                            value={day.title}
                            onChange={(e) => handleDayDetailChange(day.id, 'title', e.target.value)}
                            className="text-sm h-8"
                        />
                        </div>
                        <div>
                        <Label htmlFor={`${day.id}-notes`} className="text-xs font-medium text-muted-foreground">Day Notes</Label>
                        <Input
                            id={`${day.id}-notes`}
                            value={day.notes || ''}
                            placeholder="e.g. Perform as circuit..."
                            onChange={(e) => handleDayDetailChange(day.id, 'notes', e.target.value)}
                            className="text-xs italic h-8"
                        />
                        </div>
                    </div>
                    ) : (
                    <>
                        <CardTitle className="text-xl font-semibold text-primary">{getDisplayDayName(day)}</CardTitle>
                        <CardDescription className="text-sm text-muted-foreground">{day.title}</CardDescription>
                    </>
                    )}
                </CardHeader>
                <CardContent className="flex-grow space-y-3">
                    {day.notes && !isEditMode && (
                    <p className="text-xs text-muted-foreground italic mb-2 p-2 bg-secondary/30 rounded-md">{day.notes}</p>
                    )}
                    <ul className="space-y-1 text-sm">
                    {day.exercises.map((ex, index) => (
                        <li key={ex.id} className="text-muted-foreground truncate flex justify-between items-center group hover:bg-secondary/20 p-1 rounded-md">
                        <div className="flex items-center gap-1">
                            <Link href={`/exercises/${ex.id}?planId=${activePlanDetails.id}&dayId=${day.id}`} passHref legacyBehavior>
                                <a className="hover:text-primary flex items-center gap-1" target="_blank" rel="noopener noreferrer">
                                    <span>- {ex.name} <span className="text-xs">({ex.sets.length} sets)</span></span>
                                    <Info className="h-3 w-3 opacity-50 group-hover:opacity-100" />
                                </a>
                            </Link>
                        </div>
                        {isEditMode && (
                            <div className="opacity-0 group-hover:opacity-100 transition-opacity flex gap-1 items-center">
                            <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => handleMoveExerciseInActivePlan(day.id, ex.id, 'up')} disabled={index === 0}>
                                <ArrowUp className="h-3 w-3" />
                            </Button>
                            <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => handleMoveExerciseInActivePlan(day.id, ex.id, 'down')} disabled={index === day.exercises.length - 1}>
                                <ArrowDown className="h-3 w-3" />
                            </Button>
                            <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => openExerciseModal(day.id, ex)}>
                                <Edit className="h-3 w-3" />
                            </Button>
                            <Button variant="ghost" size="icon" className="h-6 w-6 text-destructive hover:text-destructive" onClick={() => handleRemoveExerciseFromActivePlan(day.id, ex.id)}>
                                <Trash2 className="h-3 w-3" />
                            </Button>
                            </div>
                        )}
                        </li>
                    ))}
                    {day.exercises.length === 0 && (
                        <li className="text-muted-foreground/70 italic">
                            {isEditMode ? "No exercises. Click 'Add Exercise' below." : "No exercises for this day."}
                        </li>
                    )}
                    </ul>
                    {isEditMode && (
                        <div className="mt-3 pt-3 border-t border-border/50">
                            <Button variant="outline" size="sm" className="w-full" onClick={() => openExerciseModal(day.id)}>
                                <PlusCircle className="mr-2 h-4 w-4" /> Add Exercise to {getDisplayDayName(day)}
                            </Button>
                        </div>
                    )}
                </CardContent>
                {!isEditMode && (
                    <CardFooter className="flex flex-col sm:flex-row gap-2 items-stretch pt-0 pb-4">
                        <Button asChild variant="ghost" className="flex-1 justify-start text-primary hover:bg-primary/10">
                            <Link href={`/workout/${day.id}`}>
                            View Day Details <ArrowRight className="ml-auto h-4 w-4" />
                            </Link>
                        </Button>
                        <Button variant="default" size="sm" className="flex-1" onClick={() => setOverrideMutation.mutate(day.id)} disabled={!user || setOverrideMutation.isPending}>
                            {setOverrideMutation.isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin"/> : <PlayCircle className="mr-2 h-4 w-4" />} Start This Session
                        </Button>
                    </CardFooter>
                )}
                </Card>
            ))}
            {isEditMode && (
                <div className="mt-8">
                <Button variant="outline" onClick={handleAddDayToActivePlan} className="w-full">
                    <PlusCircle className="mr-2 h-4 w-4" /> Add New Day to Plan
                </Button>
                </div>
            )}
            </div>
        </section>
      )}
      
      {isExerciseModalOpen && dayIdForModal && allExercisesForModal && (
        <AddExerciseModal
          isOpen={isExerciseModalOpen}
          onOpenChange={setIsExerciseModalOpen}
          onSave={(savedExercise) => handleSaveExerciseToActivePlan(dayIdForModal, savedExercise)}
          allExercises={allExercisesForModal}
          dayId={dayIdForModal}
          initialData={exerciseToEdit}
        />
      )}

      <Dialog open={isNewPlanDialogVisible} onOpenChange={setIsNewPlanDialogVisible}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Create New Workout Plan</DialogTitle>
            <DialogDescription>
              Enter a name for your new workout plan. You can add days and exercises after creating it.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="grid grid-cols-4 items-center gap-4">
              <Label htmlFor="new-plan-name" className="text-right">
                Plan Name
              </Label>
              <Input
                id="new-plan-name"
                value={newPlanNameInput}
                onChange={(e) => setNewPlanNameInput(e.target.value)}
                className="col-span-3"
                placeholder="e.g., My Strength Focus"
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setIsNewPlanDialogVisible(false)}>Cancel</Button>
            <Button onClick={handleActualCreateNewPlan} disabled={saveUserDataMutation.isPending}>
                {saveUserDataMutation.isPending ? <Loader2 className="mr-2 h-4 w-4 animate-spin"/> : "Create Plan"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
