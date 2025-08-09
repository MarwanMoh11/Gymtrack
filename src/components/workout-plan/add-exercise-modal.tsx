// src/components/workout-plan/add-exercise-modal.tsx
'use client';

import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { PlusCircle, Trash2, Edit } from 'lucide-react';
import type { Exercise, SetData, NewSetData } from '@/types/workout';
import { ScrollArea } from '../ui/scroll-area';
import { useToast } from '@/hooks/use-toast';
import { produce } from 'immer';

interface AddExerciseModalProps {
  isOpen: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (exercise: Exercise) => void;
  allExercises: Exercise[];
  dayId: string | null;
  initialData?: Exercise | null; // For editing
}

const getInitialExerciseState = (initialData?: Exercise | null): Omit<Exercise, 'id' | 'sets'> & { sets: NewSetData[], id?: string } => {
    if (initialData) {
        return {
            id: initialData.id,
            name: initialData.name,
            targetWeight: initialData.targetWeight || '',
            notes: initialData.notes || '',
            description: initialData.description || '',
            videoUrl: initialData.videoUrl || '',
            muscleGroups: initialData.muscleGroups || [],
            isCore: initialData.isCore || false,
            unit: initialData.unit || 'reps',
            sets: initialData.sets.length > 0
                ? initialData.sets.map((s, index) => ({
                    id: s.id || `set-${Date.now()}-${index}`,
                    targetReps: String(s.targetReps),
                    targetWeight: s.targetWeight || '',
                    unit: s.unit || initialData.unit || 'reps',
                }))
                : [{ id: `set-${Date.now()}-0`, targetReps: '8-12', targetWeight: '', unit: initialData.unit || 'reps' }],
        };
    }
    // Default state for a brand new exercise
    return {
        name: '',
        targetWeight: '',
        notes: '',
        description: '',
        videoUrl: '',
        muscleGroups: [],
        isCore: false,
        unit: 'reps',
        sets: [{ id: `set-${Date.now()}-0`, targetReps: '8-12', targetWeight: '', unit: 'reps' }],
    };
};

export default function AddExerciseModal({ isOpen, onOpenChange, onSave, allExercises, dayId, initialData }: AddExerciseModalProps) {
  const [exerciseData, setExerciseData] = useState(() => getInitialExerciseState(initialData));
  const [muscleGroupsInput, setMuscleGroupsInput] = useState(() => (initialData?.muscleGroups || []).join(', '));
  const [searchTerm, setSearchTerm] = useState(() => initialData?.name || '');
  const [showAutocomplete, setShowAutocomplete] = useState(false);
  const { toast } = useToast();
  
  const isEditing = useMemo(() => !!(initialData && initialData.id), [initialData]);

  useEffect(() => {
    // This effect now correctly re-initializes the modal's state whenever it's opened
    // for a new exercise (or for editing), by depending on `initialData` as well.
    if (isOpen) {
      const stateToSet = getInitialExerciseState(initialData);
      setExerciseData(stateToSet);
      setMuscleGroupsInput((stateToSet.muscleGroups || []).join(', '));
      setSearchTerm(stateToSet.name || '');
      setShowAutocomplete(!initialData); // Show autocomplete only if creating a new exercise
    }
  }, [isOpen, initialData]);

  const filteredExercises = useMemo(() => {
    if (!searchTerm) return [];
    return allExercises.filter(ex => ex.name.toLowerCase().includes(searchTerm.toLowerCase()));
  }, [searchTerm, allExercises]);

  const handleInputChange = (field: keyof Omit<Exercise, 'id' | 'sets' | 'muscleGroups'>, value: string | boolean | undefined) => {
    setExerciseData(prev => ({ ...prev, [field]: value }));
  };

  const handleMuscleGroupsChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setMuscleGroupsInput(e.target.value);
  };

  const handleSetChange = (index: number, field: keyof NewSetData, value: string) => {
    setExerciseData(
        produce(draft => {
            (draft.sets[index] as any)[field] = value;
        })
    );
  };

  const addSet = () => {
    setExerciseData(
        produce(draft => {
            draft.sets.push({ id: `set-${Date.now()}-${draft.sets.length}`, targetReps: '8-12', targetWeight: '', unit: draft.unit || 'reps' });
        })
    );
  };

  const removeSet = (index: number) => {
    if (exerciseData.sets.length <= 1) {
        toast({variant: 'destructive', title: "Cannot remove last set", description: "An exercise must have at least one set."})
        return;
    }
    setExerciseData(
        produce(draft => {
            draft.sets.splice(index, 1);
        })
    );
  };
  
  const handleAutocompleteSelect = useCallback((selectedExercise: Exercise) => {
    const stateToSet = getInitialExerciseState(selectedExercise);
    setExerciseData({ ...stateToSet, id: undefined }); 
    setMuscleGroupsInput((selectedExercise.muscleGroups || []).join(', '));
    setSearchTerm(selectedExercise.name);
    setShowAutocomplete(false);
  }, []);
  
  const handleCreateNewFromSearch = () => {
      const stateToSet = getInitialExerciseState();
      setExerciseData({ ...stateToSet, name: searchTerm });
      setShowAutocomplete(false);
  }

  const handleSubmit = () => {
    if (!exerciseData.name.trim()) {
      toast({ variant: 'destructive', title: 'Validation Error', description: 'Exercise name is required.' });
      return;
    }
    if (exerciseData.sets.some(s => !String(s.targetReps).trim())) {
      toast({ variant: 'destructive', title: 'Validation Error', description: 'Target reps/duration are required for all sets.' });
      return;
    }

    const finalMuscleGroups = muscleGroupsInput.split(',').map(s => s.trim()).filter(s => s);
    
    const newExerciseId = initialData?.id || `custom-${dayId}-${exerciseData.name.toLowerCase().replace(/\s+/g, '-')}-${Date.now()}`;
    
    const exerciseToSave: Exercise = {
      ...exerciseData,
      id: newExerciseId,
      muscleGroups: finalMuscleGroups,
      sets: exerciseData.sets.map((s, index) => ({
        id: (s.id && s.id.startsWith('set-')) ? s.id : `set-${newExerciseId}-${index}`,
        targetReps: s.targetReps,
        targetWeight: s.targetWeight,
        unit: s.unit,
        exerciseId: newExerciseId,
      })),
    };
    onSave(exerciseToSave);
  };
  
  // The form is now visible if we are editing OR if an exercise has been selected/created (i.e., name is not empty).
  const isFormVisible = isEditing || exerciseData.name;

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl h-[90vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>{isEditing ? `Edit: ${initialData?.name}` : 'Add Exercise'}</DialogTitle>
          <DialogDescription>
            {isEditing ? "Modify the details for this exercise in your plan." : "Search for an existing exercise or create a new one."}
          </DialogDescription>
        </DialogHeader>
        
        <div className="relative flex-shrink-0">
          <Label htmlFor="exerciseName">Exercise Name*</Label>
          <Input
            id="exerciseName"
            value={searchTerm}
            onChange={(e) => {
              const newSearchTerm = e.target.value;
              setSearchTerm(newSearchTerm);
              setShowAutocomplete(true);
              setExerciseData(produce(draft => { 
                  draft.name = newSearchTerm;
              }));
            }}
            onFocus={() => { if (!isEditing) setShowAutocomplete(true); }}
            onBlur={() => setTimeout(() => setShowAutocomplete(false), 200)}
            placeholder="e.g., Barbell Squat"
          />
          {showAutocomplete && !isEditing && (
            <div className="absolute z-10 w-full bg-card border border-border rounded-md mt-1 max-h-60 overflow-y-auto shadow-lg">
              {filteredExercises.length > 0 && filteredExercises.map(ex => (
                  <div key={ex.id} className="p-2 hover:bg-accent cursor-pointer" onMouseDown={() => handleAutocompleteSelect(ex)}>
                    {ex.name}
                  </div>
              ))}
              <div className="p-2 hover:bg-accent cursor-pointer text-primary font-semibold border-t" onMouseDown={handleCreateNewFromSearch}>
                <PlusCircle className="inline h-4 w-4 mr-2"/>Create new exercise: "{searchTerm}"
              </div>
            </div>
          )}
        </div>
        
        {isFormVisible ? (
          <ScrollArea className="flex-grow pr-6 -mr-6 pl-1">
            <div className="space-y-4 py-4 pr-1">
                <div>
                  <Label htmlFor="description">Description</Label>
                  <Textarea id="description" value={exerciseData.description} onChange={(e) => handleInputChange('description', e.target.value)} placeholder="Detailed explanation of the exercise..." rows={3} />
                </div>
                <div>
                  <Label htmlFor="videoUrl">Video URL (YouTube Embed)</Label>
                  <Input id="videoUrl" value={exerciseData.videoUrl} onChange={(e) => handleInputChange('videoUrl', e.target.value)} placeholder="https://www.youtube.com/embed/VIDEO_ID" />
                </div>
                <div>
                  <Label htmlFor="targetWeight">Default Target Weight (Optional)</Label>
                  <Input id="targetWeight" value={exerciseData.targetWeight} onChange={(e) => handleInputChange('targetWeight', e.target.value)} placeholder="e.g., 50 kg, Bodyweight, 5th stack" />
                </div>
                <div>
                  <Label htmlFor="muscleGroups">Muscle Groups (comma-separated)</Label>
                  <Input id="muscleGroups" value={muscleGroupsInput} onChange={handleMuscleGroupsChange} placeholder="e.g., Quads, Glutes, Hamstrings" />
                </div>
                <div>
                  <Label htmlFor="defaultUnit">Default Unit for Sets</Label>
                  <Select value={exerciseData.unit} onValueChange={(value: 'reps' | 's' | 'min') => handleInputChange('unit', value)}>
                    <SelectTrigger id="defaultUnit"><SelectValue placeholder="Select unit" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="reps">Reps</SelectItem>
                      <SelectItem value="s">Seconds (s)</SelectItem>
                      <SelectItem value="min">Minutes (min)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                    <Label>Define Sets*</Label>
                    {exerciseData.sets.map((set, index) => (
                        <div key={set.id || `temp-${index}`} className="flex items-end gap-2 p-2 border rounded-md bg-secondary/30">
                            <span className="text-sm font-medium pt-6">Set {index + 1}:</span>
                            <div className="flex-grow">
                                <Label htmlFor={`set-reps-${index}`} className="text-xs">Target Reps/Duration*</Label>
                                <Input id={`set-reps-${index}`} value={set.targetReps} onChange={(e) => handleSetChange(index, 'targetReps', e.target.value)} placeholder="e.g., 8-12 or 60" className="h-9" />
                            </div>
                            <div className="flex-grow">
                                <Label htmlFor={`set-weight-${index}`} className="text-xs">Target Weight (Optional)</Label>
                                <Input id={`set-weight-${index}`} value={set.targetWeight} onChange={(e) => handleSetChange(index, 'targetWeight', e.target.value)} placeholder="e.g., 80 kg" className="h-9" />
                            </div>
                            <div>
                                <Label htmlFor={`set-unit-${index}`} className="text-xs">Unit</Label>
                                <Select value={set.unit || exerciseData.unit} onValueChange={(value: 'reps' | 's' | 'min') => handleSetChange(index, 'unit', value)}>
                                    <SelectTrigger id={`set-unit-${index}`} className="h-9 w-[80px]"><SelectValue placeholder="Unit"/></SelectTrigger>
                                    <SelectContent>
                                        <SelectItem value="reps">Reps</SelectItem>
                                        <SelectItem value="s">Secs</SelectItem>
                                        <SelectItem value="min">Mins</SelectItem>
                                    </SelectContent>
                                </Select>
                            </div>
                            <Button variant="ghost" size="icon" onClick={() => removeSet(index)} className="text-destructive h-9 w-9"><Trash2 className="h-4 w-4" /></Button>
                        </div>
                    ))}
                    <Button type="button" variant="outline" size="sm" onClick={addSet} className="mt-2 w-full"><PlusCircle className="mr-2 h-4 w-4" /> Add Set</Button>
                </div>
            </div>
          </ScrollArea>
        ) : (
             <div className="flex-grow flex items-center justify-center text-muted-foreground text-center">
                <p>Search for an exercise to add, or create a new one.</p>
            </div>
        )}

        <DialogFooter className="pt-4 border-t flex-col-reverse sm:flex-row sm:justify-end gap-2">
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
            <Button type="button" onClick={handleSubmit} disabled={!exerciseData.name}>
                {isEditing ? 'Save Changes' : 'Add to Plan'}
            </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
