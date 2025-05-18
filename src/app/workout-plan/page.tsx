
// src/app/workout-plan/page.tsx
'use client';

import Link from 'next/link';
import { weeklyPlan as defaultWeeklyPlan, getDays as getDefaultDays, getAllExercisesFromPlan } from '@/data/workout-data';
import type { WorkoutDay, Exercise, SetData } from '@/types/workout';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { ArrowRight, CalendarDays, Edit, Save, XCircle, PlusCircle, Trash2, ArrowUp, ArrowDown, Info } from 'lucide-react';
import React, { useState, useEffect, useCallback } from 'react';
import { useToast } from '@/hooks/use-toast';
import AddExerciseModal from '@/components/workout-plan/add-exercise-modal'; // New Modal

export default function WorkoutPlanPage() {
  const [isEditMode, setIsEditMode] = useState(false);
  const [editablePlan, setEditablePlan] = useState<WorkoutDay[]>(() => JSON.parse(JSON.stringify(defaultWeeklyPlan)));
  const [initialPlan, setInitialPlan] = useState<WorkoutDay[]>(() => JSON.parse(JSON.stringify(defaultWeeklyPlan)));

  const [isAddExerciseModalOpen, setIsAddExerciseModalOpen] = useState(false);
  const [dayIdForNewExercise, setDayIdForNewExercise] = useState<string | null>(null);
  
  const allExercisesForAutocomplete = useMemo(() => getAllExercisesFromPlan(), []);


  const { toast } = useToast();

  useEffect(() => {
    const deepClonedPlan = JSON.parse(JSON.stringify(defaultWeeklyPlan));
    setEditablePlan(deepClonedPlan);
    setInitialPlan(deepClonedPlan);
  }, []);


  const handleDayDetailChange = (dayId: string, field: 'dayName' | 'title' | 'notes', value: string) => {
    setEditablePlan(prevPlan =>
      prevPlan.map(day =>
        day.id === dayId ? { ...day, [field]: value } : day
      )
    );
  };

  const handleSaveChanges = () => {
    console.log("Saving customized plan (client-side):", editablePlan);
    setInitialPlan(JSON.parse(JSON.stringify(editablePlan)));
    setIsEditMode(false);
    toast({
      title: "Plan Changes Applied",
      description: "Your workout plan has been updated on this page. Persistence to backend is a future step.",
    });
  };

  const handleCancelChanges = () => {
    setEditablePlan(JSON.parse(JSON.stringify(initialPlan)));
    setIsEditMode(false);
    toast({
      title: "Changes Canceled",
      description: "Your modifications to the workout plan have been discarded.",
      variant: "default",
    });
  };
  
  const handleEditExercise = (dayId: string, exerciseId: string) => {
    toast({ title: "Placeholder", description: `Editing exercise ${exerciseId} for day ${dayId} will be implemented next.`});
    // Future: Open a modal similar to AddExerciseModal but pre-filled with existing exercise data.
  };
  
  const handleRemoveExercise = (dayId: string, exerciseId: string) => {
    setEditablePlan(prevPlan =>
      prevPlan.map(day => {
        if (day.id === dayId) {
          return { ...day, exercises: day.exercises.filter(ex => ex.id !== exerciseId) };
        }
        return day;
      })
    );
    toast({ title: "Exercise Removed", description: `Exercise removed from ${dayId}. Save changes to apply.`});
  };
   
  const handleAddExerciseClick = (dayId: string) => {
    setDayIdForNewExercise(dayId);
    setIsAddExerciseModalOpen(true);
  };

  const handleSaveNewExercise = (dayId: string, newExercise: Exercise) => {
    setEditablePlan(prevPlan =>
      prevPlan.map(day => {
        if (day.id === dayId) {
          return { ...day, exercises: [...day.exercises, newExercise] };
        }
        return day;
      })
    );
    setIsAddExerciseModalOpen(false);
    setDayIdForNewExercise(null);
    toast({ title: "Exercise Added", description: `${newExercise.name} added to ${dayId}. Save changes to apply.`});
  };

  const handleMoveExercise = (dayId: string, exerciseId: string, direction: 'up' | 'down') => {
    setEditablePlan(prevPlan => {
      return prevPlan.map(day => {
        if (day.id === dayId) {
          const exercises = [...day.exercises];
          const index = exercises.findIndex(ex => ex.id === exerciseId);
          if (index === -1) return day;

          if (direction === 'up' && index > 0) {
            const temp = exercises[index];
            exercises[index] = exercises[index - 1];
            exercises[index - 1] = temp;
          } else if (direction === 'down' && index < exercises.length - 1) {
            const temp = exercises[index];
            exercises[index] = exercises[index + 1];
            exercises[index + 1] = temp;
          }
          return { ...day, exercises };
        }
        return day;
      });
    });
  };

  return (
    <div className="container mx-auto py-8 px-4 md:px-6">
      <header className="mb-8 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h1 className="text-3xl font-bold text-primary flex items-center">
            <CalendarDays className="mr-3 h-8 w-8" />
            Full Workout Plan
          </h1>
          <p className="text-muted-foreground mt-1">
            {isEditMode ? "Customize your weekly workout schedule." : "Browse through all the workout days in your plan."}
          </p>
        </div>
        <div className="flex gap-2">
          {isEditMode ? (
            <>
              <Button onClick={handleSaveChanges} variant="default" size="sm">
                <Save className="mr-2 h-4 w-4" /> Save Changes
              </Button>
              <Button onClick={handleCancelChanges} variant="outline" size="sm">
                <XCircle className="mr-2 h-4 w-4" /> Cancel
              </Button>
            </>
          ) : (
            <Button onClick={() => setIsEditMode(true)} variant="outline" size="sm">
              <Edit className="mr-2 h-4 w-4" /> Edit Plan
            </Button>
          )}
        </div>
      </header>

      {editablePlan.length === 0 ? (
        <Card className="shadow-lg rounded-2xl">
          <CardHeader>
            <CardTitle className="text-xl font-semibold">No Workout Plan Found</CardTitle>
          </CardHeader>
          <CardContent className="text-center py-12">
            <p className="text-muted-foreground">
              It seems there's no workout plan configured. Please check the application setup.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-8">
          {editablePlan.map((day) => (
            <Card key={day.id} className="shadow-lg rounded-2xl flex flex-col">
              <CardHeader>
                {isEditMode ? (
                  <div className="space-y-3">
                    <div>
                      <Label htmlFor={`${day.id}-dayName`} className="text-xs font-medium text-muted-foreground">Day Name</Label>
                      <Input
                        id={`${day.id}-dayName`}
                        value={day.dayName}
                        onChange={(e) => handleDayDetailChange(day.id, 'dayName', e.target.value)}
                        className="text-xl font-semibold text-primary h-9"
                      />
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
                    <CardTitle className="text-xl font-semibold text-primary">{day.dayName}</CardTitle>
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
                        <Link href={`/exercises/${ex.id}`} passHref legacyBehavior>
                            <a className="hover:text-primary flex items-center gap-1" target="_blank" rel="noopener noreferrer">
                                <span>- {ex.name} <span className="text-xs">({ex.sets.length} sets)</span></span>
                                <Info className="h-3 w-3 opacity-50 group-hover:opacity-100" />
                            </a>
                        </Link>
                      </div>
                      {isEditMode && (
                        <div className="opacity-0 group-hover:opacity-100 transition-opacity flex gap-1 items-center">
                           <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => handleMoveExercise(day.id, ex.id, 'up')} disabled={index === 0}>
                                <ArrowUp className="h-3 w-3" />
                           </Button>
                           <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => handleMoveExercise(day.id, ex.id, 'down')} disabled={index === day.exercises.length - 1}>
                                <ArrowDown className="h-3 w-3" />
                           </Button>
                           <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => handleEditExercise(day.id, ex.id)}>
                                <Edit className="h-3 w-3" />
                           </Button>
                           <Button variant="ghost" size="icon" className="h-6 w-6 text-destructive hover:text-destructive" onClick={() => handleRemoveExercise(day.id, ex.id)}>
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
                        <Button variant="outline" size="sm" className="w-full" onClick={() => handleAddExerciseClick(day.id)}>
                            <PlusCircle className="mr-2 h-4 w-4" /> Add Exercise to {day.dayName}
                        </Button>
                    </div>
                )}
              </CardContent>
              {!isEditMode && (
                <CardContent className="pt-0 pb-4">
                  <Button asChild variant="ghost" className="w-full justify-start text-primary hover:bg-primary/10">
                    <Link href={`/workout/${day.id}`}>
                      View {day.dayName}'s Workout <ArrowRight className="ml-auto h-4 w-4" />
                    </Link>
                  </Button>
                </CardContent>
              )}
            </Card>
          ))}
        </div>
      )}
       {isAddExerciseModalOpen && dayIdForNewExercise && (
        <AddExerciseModal
          isOpen={isAddExerciseModalOpen}
          onOpenChange={setIsAddExerciseModalOpen}
          onSave={(newExercise) => handleSaveNewExercise(dayIdForNewExercise, newExercise)}
          allExercises={allExercisesForAutocomplete}
          dayId={dayIdForNewExercise}
        />
      )}
    </div>
  );
}
