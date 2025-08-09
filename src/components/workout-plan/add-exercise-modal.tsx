// src/components/workout-plan/add-exercise-modal.tsx
'use client';

import React, { useState, useEffect, useMemo } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter, DialogClose } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { X, PlusCircle, Trash2 } from 'lucide-react';
import type { Exercise, SetData, NewSetData } from '@/types/workout';
import { ScrollArea } from '../ui/scroll-area';
import { useToast } from '@/hooks/use-toast';

interface AddExerciseModalProps {
  isOpen: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (exercise: Exercise) => void;
  allExercises: Exercise[];
  dayId: string;
  initialData?: Exercise | null; // For editing
}

const getInitialExerciseState = (initialData?: Exercise | null): Omit<Exercise, 'id' | 'sets'> & { sets: NewSetData[], id?: string } => {
  if (initialData) {
    console.log('[AddExerciseModal] Initializing state from initialData:', initialData);
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
      sets: initialData.sets.map((s, index) => ({
        id: s.id || `set-${Date.now()}-${index}`,
        targetReps: String(s.targetReps),
        targetWeight: s.targetWeight || '',
        unit: s.unit || initialData.unit || 'reps',
      })),
    };
  }
  console.log('[AddExerciseModal] Initializing new exercise state.');
  return {
    name: '',
    targetWeight: '',
    notes: '',
    description: '',
    videoUrl: '',
    muscleGroups: [],
    isCore: false,
    unit: 'reps',
    sets: [{ id: `set-${Date.now()}-0`, targetReps: '', targetWeight: '', unit: 'reps' }],
  };
};


export default function AddExerciseModal({ isOpen, onOpenChange, onSave, allExercises, dayId, initialData }: AddExerciseModalProps) {
  // Key change: Initialize state based on initialData directly.
  // This state is now "local" to each render of the open dialog.
  const [exerciseData, setExerciseData] = useState(() => getInitialExerciseState(initialData));
  const [muscleGroupsInput, setMuscleGroupsInput] = useState(() => (initialData?.muscleGroups || []).join(', '));
  const [searchTerm, setSearchTerm] = useState(() => initialData?.name || '');
  const [showAutocomplete, setShowAutocomplete] = useState(false);
  const { toast } = useToast();
  
  const isEditing = !!initialData;

  // This effect ensures that if the modal is re-opened with different data, the state updates.
  useEffect(() => {
      console.log('[AddExerciseModal useEffect] isOpen changed to:', isOpen, 'initialData ID:', initialData?.id);
      if (isOpen) {
          const stateToSet = getInitialExerciseState(initialData);
          setExerciseData(stateToSet);
          setMuscleGroupsInput((stateToSet.muscleGroups || []).join(', '));
          setSearchTerm(stateToSet.name || '');
          setShowAutocomplete(false); // Reset autocomplete on open
      }
  }, [isOpen, initialData]);


  const filteredExercises = useMemo(() => {
    if (!searchTerm || isEditing) return [];
    return allExercises.filter(ex => ex.name.toLowerCase().includes(searchTerm.toLowerCase()));
  }, [searchTerm, allExercises, isEditing]);

  const handleInputChange = (field: keyof Omit<Exercise, 'id' | 'sets' | 'muscleGroups'>, value: string | boolean | undefined) => {
    setExerciseData(prev => ({ ...prev, [field]: value }));
  };

  const handleMuscleGroupsChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setMuscleGroupsInput(e.target.value);
  };

  const handleSetChange = (index: number, field: keyof NewSetData, value: string) => {
    const newSets = [...exerciseData.sets];
    // @ts-ignore
    newSets[index][field] = value;
    setExerciseData(prev => ({ ...prev, sets: newSets }));
  };

  const addSet = () => {
    setExerciseData(prev => ({
      ...prev,
      sets: [...prev.sets, { id: `set-${Date.now()}-${prev.sets.length}`, targetReps: '', targetWeight: '', unit: prev.unit || 'reps' }],
    }));
  };

  const removeSet = (index: number) => {
    if (exerciseData.sets.length <= 1) {
        toast({variant: 'destructive', title: "Cannot remove last set", description: "An exercise must have at least one set."})
        return;
    }
    setExerciseData(prev => ({ ...prev, sets: prev.sets.filter((_, i) => i !== index) }));
  };

  const handleAutocompleteSelect = (selectedExercise: Exercise) => {
    console.log('[AddExerciseModal] Autocomplete selected:', selectedExercise.name);
    // When selecting from autocomplete, we reset the state based on the template,
    // but ensure it's treated as a "new" exercise by clearing the ID.
    const newState = getInitialExerciseState(selectedExercise);
    setExerciseData({ ...newState, id: undefined }); 
    setMuscleGroupsInput((selectedExercise.muscleGroups || []).join(', '));
    setSearchTerm(selectedExercise.name);
    setShowAutocomplete(false);
  };

  const handleSubmit = () => {
    console.log('[AddExerciseModal] handleSubmit called.');
    if (!exerciseData.name.trim()) {
      toast({ variant: 'destructive', title: 'Validation Error', description: 'Exercise name is required.' });
      return;
    }
    if (exerciseData.sets.some(s => !String(s.targetReps).trim())) {
      toast({ variant: 'destructive', title: 'Validation Error', description: 'Target reps/duration are required for all sets.' });
      return;
    }

    const finalMuscleGroups = muscleGroupsInput.split(',').map(s => s.trim()).filter(s => s);
    
    // Use the initialData ID if editing, otherwise generate a new one.
    const newExerciseId = initialData?.id || `custom-${dayId}-${exerciseData.name.toLowerCase().replace(/\s+/g, '-')}-${Date.now()}`;
    
    const exerciseToSave: Exercise = {
      ...exerciseData,
      id: newExerciseId,
      muscleGroups: finalMuscleGroups,
      sets: exerciseData.sets.map((s, index) => ({
        // Preserve existing set IDs if they exist (during edit), otherwise generate new ones.
        id: (initialData?.sets[index]?.id && s.id.startsWith('set-')) ? initialData.sets[index].id : s.id,
        targetReps: s.targetReps,
        targetWeight: s.targetWeight,
        unit: s.unit,
        exerciseId: newExerciseId,
      })),
    };
    console.log('[AddExerciseModal] Saving exercise:', exerciseToSave);
    onSave(exerciseToSave);
  };

  return (
    <Dialog open={isOpen} onOpenChange={(open) => {
      onOpenChange(open);
    }}>
      <DialogContent className="max-w-2xl h-[90vh] flex flex-col">
        <DialogHeader>
          <DialogTitle>{isEditing ? 'Edit Exercise' : 'Add New Exercise to Plan'}</DialogTitle>
          <DialogDescription>Define the details for the exercise.</DialogDescription>
        </DialogHeader>
        <ScrollArea className="flex-grow pr-6 -mr-6 pl-1">
          <div className="space-y-4 py-4 pr-1">
            <div className="relative">
              <Label htmlFor="exerciseName">Exercise Name*</Label>
              <Input
                id="exerciseName"
                value={searchTerm}
                onChange={(e) => {
                  setSearchTerm(e.target.value);
                  handleInputChange('name', e.target.value);
                  if (!isEditing) setShowAutocomplete(true);
                }}
                onFocus={() => { if (!isEditing) setShowAutocomplete(true); }}
                onBlur={() => setTimeout(() => setShowAutocomplete(false), 200)}
                placeholder="e.g., Barbell Squat"
              />
              {showAutocomplete && filteredExercises.length > 0 && searchTerm && !isEditing && (
                <div className="absolute z-10 w-full bg-card border border-border rounded-md mt-1 max-h-40 overflow-y-auto shadow-lg">
                  {filteredExercises.map(ex => (
                    <div
                      key={ex.id}
                      className="p-2 hover:bg-accent cursor-pointer"
                      onMouseDown={() => handleAutocompleteSelect(ex)} // use onMouseDown to fire before onBlur
                    >
                      {ex.name}
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div>
              <Label htmlFor="description">Description</Label>
              <Textarea
                id="description"
                value={exerciseData.description}
                onChange={(e) => handleInputChange('description', e.target.value)}
                placeholder="Detailed explanation of the exercise..."
                rows={3}
              />
            </div>

            <div>
              <Label htmlFor="videoUrl">Video URL (YouTube Embed)</Label>
              <Input
                id="videoUrl"
                value={exerciseData.videoUrl}
                onChange={(e) => handleInputChange('videoUrl', e.target.value)}
                placeholder="https://www.youtube.com/embed/VIDEO_ID"
              />
            </div>
            
            <div>
              <Label htmlFor="targetWeight">Default Target Weight (Optional)</Label>
              <Input
                id="targetWeight"
                value={exerciseData.targetWeight}
                onChange={(e) => handleInputChange('targetWeight', e.target.value)}
                placeholder="e.g., 50 kg, Bodyweight, 5th stack"
              />
            </div>

            <div>
              <Label htmlFor="muscleGroups">Muscle Groups (comma-separated)</Label>
              <Input
                id="muscleGroups"
                value={muscleGroupsInput}
                onChange={handleMuscleGroupsChange}
                placeholder="e.g., Quads, Glutes, Hamstrings"
              />
            </div>

            <div>
              <Label htmlFor="defaultUnit">Default Unit for Sets</Label>
              <Select
                value={exerciseData.unit}
                onValueChange={(value: 'reps' | 's' | 'min') => handleInputChange('unit', value)}
              >
                <SelectTrigger id="defaultUnit">
                  <SelectValue placeholder="Select unit" />
                </SelectTrigger>
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
                            <Input
                                id={`set-reps-${index}`}
                                value={set.targetReps}
                                onChange={(e) => handleSetChange(index, 'targetReps', e.target.value)}
                                placeholder="e.g., 8-12 or 60"
                                className="h-9"
                            />
                        </div>
                        <div className="flex-grow">
                            <Label htmlFor={`set-weight-${index}`} className="text-xs">Target Weight (Optional)</Label>
                            <Input
                                id={`set-weight-${index}`}
                                value={set.targetWeight}
                                onChange={(e) => handleSetChange(index, 'targetWeight', e.target.value)}
                                placeholder="e.g., 80 kg"
                                className="h-9"
                            />
                        </div>
                        <div>
                             <Label htmlFor={`set-unit-${index}`} className="text-xs">Unit</Label>
                             <Select
                                value={set.unit || exerciseData.unit}
                                onValueChange={(value: 'reps' | 's' | 'min') => handleSetChange(index, 'unit', value)}
                             >
                                <SelectTrigger id={`set-unit-${index}`} className="h-9 w-[80px]">
                                    <SelectValue placeholder="Unit"/>
                                </SelectTrigger>
                                <SelectContent>
                                    <SelectItem value="reps">Reps</SelectItem>
                                    <SelectItem value="s">Secs</SelectItem>
                                    <SelectItem value="min">Mins</SelectItem>
                                </SelectContent>
                             </Select>
                        </div>
                        <Button variant="ghost" size="icon" onClick={() => removeSet(index)} className="text-destructive h-9 w-9">
                            <Trash2 className="h-4 w-4" />
                        </Button>
                    </div>
                ))}
                <Button type="button" variant="outline" size="sm" onClick={addSet} className="mt-2 w-full">
                    <PlusCircle className="mr-2 h-4 w-4" /> Add Set
                </Button>
            </div>

          </div>
        </ScrollArea>
        <DialogFooter className="pt-4 border-t">
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button type="button" onClick={handleSubmit}>Save Exercise</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
