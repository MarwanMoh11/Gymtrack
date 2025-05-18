
// src/app/workout-plan/page.tsx
'use client';

import Link from 'next/link';
import { weeklyPlan as defaultWeeklyPlan, getDays as getDefaultDays } from '@/data/workout-data';
import type { WorkoutDay } from '@/types/workout';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { ArrowRight, CalendarDays, Edit, Save, XCircle, PlusCircle, Trash2 } from 'lucide-react';
import React, { useState, useEffect } from 'react';
import { useToast } from '@/hooks/use-toast';

export default function WorkoutPlanPage() {
  const [isEditMode, setIsEditMode] = useState(false);
  const [editablePlan, setEditablePlan] = useState<WorkoutDay[]>(() => JSON.parse(JSON.stringify(defaultWeeklyPlan))); // Deep copy
  const [initialPlan, setInitialPlan] = useState<WorkoutDay[]>(() => JSON.parse(JSON.stringify(defaultWeeklyPlan))); // For cancel

  const { toast } = useToast();

  // Reset editablePlan if defaultWeeklyPlan changes (e.g. hot-reload of data file)
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
    // In a real app, here you would send editablePlan to your backend/Firestore to save it.
    setInitialPlan(JSON.parse(JSON.stringify(editablePlan))); // Update initial plan to current saved state
    setIsEditMode(false);
    toast({
      title: "Plan Changes Applied",
      description: "Your workout plan has been updated on this page. Persistence to backend is a future step.",
    });
  };

  const handleCancelChanges = () => {
    setEditablePlan(JSON.parse(JSON.stringify(initialPlan))); // Revert to last saved or default state
    setIsEditMode(false);
    toast({
      title: "Changes Canceled",
      description: "Your modifications to the workout plan have been discarded.",
      variant: "default",
    });
  };
  
  // Placeholder for future exercise/set editing logic
  const handleEditExercise = (dayId: string, exerciseId: string) => {
    toast({ title: "Action Placeholder", description: `Edit exercise ${exerciseId} for day ${dayId}`});
  };
  const handleRemoveExercise = (dayId: string, exerciseId: string) => {
     toast({ title: "Action Placeholder", description: `Remove exercise ${exerciseId} from day ${dayId}`});
  };
   const handleAddExercise = (dayId: string) => {
    toast({ title: "Action Placeholder", description: `Add exercise to day ${dayId}`});
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
                  {day.exercises.map((ex) => (
                    <li key={ex.id} className="text-muted-foreground truncate flex justify-between items-center group hover:bg-secondary/20 p-1 rounded-md">
                      <span>- {ex.name} <span className="text-xs">({ex.sets.length} sets)</span></span>
                      {isEditMode && (
                        <div className="opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                           {/* Placeholders for exercise editing actions */}
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
                  {day.exercises.length === 0 && !isEditMode && (
                    <li className="text-muted-foreground/70 italic">No exercises for this day.</li>
                  )}
                </ul>
                 {isEditMode && (
                    <div className="mt-3 pt-3 border-t border-border/50">
                        <Button variant="outline" size="sm" className="w-full" onClick={() => handleAddExercise(day.id)}>
                            <PlusCircle className="mr-2 h-4 w-4" /> Add Exercise to {day.dayName}
                        </Button>
                        {/* More detailed set editing would go here per exercise when an exercise is "expanded" or selected for edit */}
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
    </div>
  );
}

