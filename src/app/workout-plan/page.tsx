
// src/app/workout-plan/page.tsx
'use client';

import Link from 'next/link';
import { getAllNamedWorkoutPlans, setActiveWorkoutPlan, getActiveNamedWorkoutPlan, updateActiveWorkoutPlan, createNewWorkoutPlan } from '@/lib/workout-plan-service';
import type { WorkoutDay, Exercise, NamedWorkoutPlan } from '@/types/workout';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Separator } from '@/components/ui/separator';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { ArrowRight, CalendarDays, Edit, Save, XCircle, PlusCircle, Trash2, ArrowUp, ArrowDown, Info, CheckCircle, WandSparkles } from 'lucide-react';
import React, { useState, useEffect, useMemo } from 'react';
import { useToast } from '@/hooks/use-toast';
import AddExerciseModal from '@/components/workout-plan/add-exercise-modal';
import { getAllExercisesFromPlan as getAllExercisesForAutocompleteGlobal } from '@/data/workout-data';
import { produce } from 'immer';

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
  const [allPlans, setAllPlans] = useState<NamedWorkoutPlan[]>([]);
  const [activePlanDetails, setActivePlanDetails] = useState<NamedWorkoutPlan | null>(null);
  
  const [isEditMode, setIsEditMode] = useState(false);
  const [editableActivePlan, setEditableActivePlan] = useState<WorkoutDay[]>([]);
  const [initialActivePlanForEdit, setInitialActivePlanForEdit] = useState<WorkoutDay[]>([]);

  const [isExerciseModalOpen, setIsExerciseModalOpen] = useState(false);
  const [dayIdForModal, setDayIdForModal] = useState<string | null>(null);
  const [exerciseToEdit, setExerciseToEdit] = useState<Exercise | null>(null);
  
  const [isNewPlanDialogVisible, setIsNewPlanDialogVisible] = useState(false);
  const [newPlanNameInput, setNewPlanNameInput] = useState('');

  const allExercisesForModalAutocomplete = useMemo(() => getAllExercisesForAutocompleteGlobal(), []);

  const { toast } = useToast();

  const refreshPlans = () => {
    const plans = getAllNamedWorkoutPlans();
    setAllPlans(plans);
    const currentActive = plans.find(p => p.isActive) || (plans.length > 0 ? plans[0] : null);
    setActivePlanDetails(currentActive);
    if (currentActive) {
      const clonedPlan = JSON.parse(JSON.stringify(currentActive.plan));
      setEditableActivePlan(clonedPlan);
      setInitialActivePlanForEdit(clonedPlan);
    } else {
      setEditableActivePlan([]);
      setInitialActivePlanForEdit([]);
    }
  };

  useEffect(() => {
    refreshPlans();
  }, []);

  const handleSetPlanActive = (planId: string) => {
    setActiveWorkoutPlan(planId);
    refreshPlans();
    setIsEditMode(false); // Exit edit mode when switching active plan
    toast({ title: "Active Plan Switched", description: `The active workout plan has been updated.` });
  };

  // --- Editing logic for the *active* plan ---
  const handleDayDetailChange = (dayId: string, field: keyof WorkoutDay, value: string | number | undefined) => {
    setEditableActivePlan(
      produce(editableActivePlan, draft => {
        const day = draft.find(d => d.id === dayId);
        if (day) {
          if (field === 'mapsToActualDayOfWeek') {
            (day as any)[field] = value;
            // Also update dayName based on the selected day of the week
            const selectedDayObj = daysOfWeekMap.find(d => d.value === value);
            day.dayName = selectedDayObj && selectedDayObj.value !== -1 ? selectedDayObj.name : "Unassigned Day";
          } else {
            (day as any)[field] = value;
          }
        }
      })
    );
  };

  const handleSaveChangesToActivePlan = () => {
    if (activePlanDetails) {
      updateActiveWorkoutPlan(editableActivePlan); 
      setInitialActivePlanForEdit(JSON.parse(JSON.stringify(editableActivePlan)));
      setIsEditMode(false);
      toast({
        title: "Active Plan Updated",
        description: `Changes to '${activePlanDetails.name}' have been saved.`,
      });
      refreshPlans(); 
    }
  };

  const handleCancelChangesToActivePlan = () => {
    setEditableActivePlan(JSON.parse(JSON.stringify(initialActivePlanForEdit)));
    setIsEditMode(false);
    toast({
      title: "Changes Canceled",
      description: "Modifications to the active plan have been discarded.",
      variant: "default",
    });
  };
  
  const openExerciseModal = (dayId: string, exercise?: Exercise) => {
    setDayIdForModal(dayId);
    setExerciseToEdit(exercise || null);
    setIsExerciseModalOpen(true);
  };
  
  const handleRemoveExerciseFromActivePlan = (dayId: string, exerciseId: string) => {
    setEditableActivePlan(
      produce(editableActivePlan, draft => {
        const day = draft.find(d => d.id === dayId);
        if (day) {
          day.exercises = day.exercises.filter(ex => ex.id !== exerciseId);
        }
      })
    );
    toast({ title: "Exercise Removed", description: `Exercise removed from ${dayId}. Save changes to apply.`});
  };
   
  const handleSaveExerciseToActivePlan = (dayId: string, savedExercise: Exercise) => {
     setEditableActivePlan(
      produce(editableActivePlan, draft => {
        const day = draft.find(d => d.id === dayId);
        if (day) {
          const existingExerciseIndex = day.exercises.findIndex(ex => ex.id === savedExercise.id);
          if (existingExerciseIndex !== -1) { // Editing existing
            day.exercises[existingExerciseIndex] = savedExercise;
          } else { // Adding new
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
      description: `${savedExercise.name} ${exerciseToEdit ? 'updated in' : 'added to'} active plan. Save changes to apply.`
    });
  };

  const handleMoveExerciseInActivePlan = (dayId: string, exerciseId: string, direction: 'up' | 'down') => {
    setEditableActivePlan(
      produce(editableActivePlan, draft => {
        const day = draft.find(d => d.id === dayId);
        if (day) {
          const exercises = day.exercises;
          const index = exercises.findIndex(ex => ex.id === exerciseId);
          if (index === -1) return;

          if (direction === 'up' && index > 0) {
            [exercises[index], exercises[index - 1]] = [exercises[index - 1], exercises[index]];
          } else if (direction === 'down' && index < exercises.length - 1) {
            [exercises[index], exercises[index + 1]] = [exercises[index + 1], exercises[index]];
          }
        }
      })
    );
  };

  const triggerCreateNewPlanModal = () => {
    setNewPlanNameInput('');
    setIsNewPlanDialogVisible(true);
  };

  const handleActualCreateNewPlan = () => {
    if (!newPlanNameInput.trim()) {
      toast({ variant: 'destructive', title: 'Plan Name Required', description: 'Please enter a name for the new plan.' });
      return;
    }
    createNewWorkoutPlan(newPlanNameInput.trim());
    refreshPlans();
    toast({ title: "New Plan Created", description: `Plan '${newPlanNameInput.trim()}' added. You can now set it as active and edit it.` });
    setIsNewPlanDialogVisible(false);
    setNewPlanNameInput('');
  };

  const handleAddDayToActivePlan = () => {
    const newDayId = `custom-day-${Date.now()}`;
    const newDay: WorkoutDay = {
      id: newDayId,
      dayName: 'New Day', // This will be updated if assigned via dropdown
      title: 'Workout Title (Click to Edit)',
      exercises: [],
      notes: 'Add exercises and notes for this day.',
      mapsToActualDayOfWeek: -1, // Default to Unassigned
    };
    setEditableActivePlan(
      produce(editableActivePlan, draft => {
        draft.push(newDay);
      })
    );
    toast({ title: "New Day Added", description: "A new day has been added to the plan. Edit its details and add exercises. Don't forget to save plan changes." });
  };

  const getDisplayDayName = (day: WorkoutDay): string => {
    if (day.mapsToActualDayOfWeek !== undefined && day.mapsToActualDayOfWeek !== -1) {
      const mapped = daysOfWeekMap.find(d => d.value === day.mapsToActualDayOfWeek);
      return mapped ? mapped.name : day.dayName;
    }
    return day.dayName;
  };

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
        <Button onClick={triggerCreateNewPlanModal} variant="outline" size="sm">
          <PlusCircle className="mr-2 h-4 w-4" /> Create New Plan
        </Button>
      </header>

      <section className="mb-12">
        <h2 className="text-2xl font-semibold mb-4 text-secondary-foreground">Available Plans</h2>
        {allPlans.length === 0 ? (
          <p className="text-muted-foreground">No workout plans found. Default plans should load or you can create one.</p>
        ) : (
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
                    disabled={plan.isActive}
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
        )}
      </section>
      
      <Separator className="my-8" />

      {activePlanDetails && (
        <section>
            <header className="mb-6 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
                <div>
                <h2 className="text-2xl font-semibold text-primary flex items-center">
                    <CalendarDays className="mr-3 h-7 w-7" />
                    Editing: {activePlanDetails.name}
                </h2>
                <p className="text-muted-foreground mt-1">
                    {isEditMode ? "Customize your weekly schedule for the active plan." : "Browse the active workout plan."}
                </p>
                </div>
                <div className="flex gap-2">
                {isEditMode ? (
                    <>
                    <Button onClick={handleSaveChangesToActivePlan} variant="default" size="sm">
                        <Save className="mr-2 h-4 w-4" /> Save Changes
                    </Button>
                    <Button onClick={handleCancelChangesToActivePlan} variant="outline" size="sm">
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

            {editableActivePlan.length === 0 && activePlanDetails.plan.length === 0 && !isEditMode ? (
                <Card className="shadow-lg rounded-2xl">
                <CardHeader><CardTitle className="text-xl font-semibold">Empty Plan</CardTitle></CardHeader>
                <CardContent className="text-center py-12">
                    <p className="text-muted-foreground">This plan is empty. Click "Edit Active Plan" to add days and exercises.</p>
                </CardContent>
                </Card>
            ) : (
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
                        <CardContent className="pt-0 pb-4">
                        <Button asChild variant="ghost" className="w-full justify-start text-primary hover:bg-primary/10">
                            <Link href={`/workout/${day.id}`}>
                            View {getDisplayDayName(day)}'s Workout <ArrowRight className="ml-auto h-4 w-4" />
                            </Link>
                        </Button>
                        </CardContent>
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
            )}
        </section>
      )}

      {isExerciseModalOpen && dayIdForModal && activePlanDetails && (
        <AddExerciseModal
          isOpen={isExerciseModalOpen}
          onOpenChange={setIsExerciseModalOpen}
          onSave={(savedExercise) => handleSaveExerciseToActivePlan(dayIdForModal, savedExercise)}
          allExercises={allExercisesForModalAutocomplete}
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
            <Button onClick={handleActualCreateNewPlan}>Create Plan</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

    </div>
  );
}

