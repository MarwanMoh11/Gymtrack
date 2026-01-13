// src/components/workout-plan/add-exercise-modal.tsx
'use client';

import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { PlusCircle, Trash2, Edit, Dumbbell, Search } from 'lucide-react';
import type { PlanExercise, GlobalExercise, NewSetData } from '../../types/workout';
import { ScrollArea } from '../ui/scroll-area';
import { useToast } from '@/hooks/use-toast';
import { produce } from 'immer';
import { getGlobalExercises } from '@/lib/firestore-workout-plan-service';
import { Badge } from '@/components/ui/badge';

interface AddExerciseModalProps {
  isOpen: boolean;
  onOpenChange: (open: boolean) => void;
  onSave: (exercise: PlanExercise) => void;
  dayId: string | null;
  initialData?: PlanExercise | null; // For editing
}

const getInitialExerciseState = (initialData?: PlanExercise | Partial<GlobalExercise> | null): Omit<PlanExercise, 'id' | 'sets'> & { sets: NewSetData[], id?: string, globalExerciseId?: string } => {
  if (initialData) {
    const sets = (initialData as any).sets?.length > 0
      ? (initialData as any).sets.map((s: any, index: number) => ({
        id: s.id || `set-${Date.now()}-${index}`,
        targetReps: String(s.targetReps),
        targetWeight: s.targetWeight || '',
        unit: s.unit || (initialData as any).defaultUnit || 'reps',
      }))
      : [{ id: `set-${Date.now()}-0`, targetReps: '8-12', targetWeight: '', unit: (initialData as any).defaultUnit || 'reps' }];

    return {
      id: (initialData as any).id, // Only present if editing PlanExercise
      globalExerciseId: (initialData as any).globalExerciseId || (initialData as any).id, // Use global ID if mapping from GlobalExercise
      name: initialData.name || '',
      targetWeight: (initialData as any).targetWeight || '',
      notes: (initialData as any).notes || '',
      description: initialData.description || '',
      videoUrl: initialData.videoUrl || '',
      muscleGroups: initialData.muscleGroups || [],
      // isCore property is deprecated, derived from category or manually set muscle groups, ignoring for now or mapping
      unit: (initialData as any).unit || (initialData as any).defaultUnit || 'reps',
      sets,
    };
  }
  // Default state for a brand new custom exercise
  return {
    name: '',
    globalExerciseId: 'custom',
    category: 'custom',
    targetWeight: '',
    notes: '',
    description: '',
    videoUrl: '',
    muscleGroups: [],
    unit: 'reps',
    sets: [{ id: `set-${Date.now()}-0`, targetReps: '8-12', targetWeight: '', unit: 'reps' }],
  };
};

export default function AddExerciseModal({ isOpen, onOpenChange, onSave, dayId, initialData }: AddExerciseModalProps) {
  const [exerciseData, setExerciseData] = useState(() => getInitialExerciseState(initialData));
  const [muscleGroupsInput, setMuscleGroupsInput] = useState(() => (initialData?.muscleGroups || []).join(', '));
  const [searchTerm, setSearchTerm] = useState(() => initialData?.name || '');
  const [showAutocomplete, setShowAutocomplete] = useState(false);

  const [globalLibrary, setGlobalLibrary] = useState<GlobalExercise[]>([]);

  const { toast } = useToast();

  const isEditing = useMemo(() => !!(initialData && initialData.id), [initialData]);

  // Fetch global exercises on mount
  useEffect(() => {
    let mounted = true;
    if (isOpen && !globalLibrary.length) {
      getGlobalExercises().then(exercises => {
        if (mounted) setGlobalLibrary(exercises);
      });
    }
    return () => { mounted = false; };
  }, [isOpen, globalLibrary.length]);

  useEffect(() => {
    if (isOpen) {
      const stateToSet = getInitialExerciseState(initialData);
      setExerciseData(stateToSet);
      setMuscleGroupsInput((stateToSet.muscleGroups || []).join(', '));
      setSearchTerm(stateToSet.name || '');
      setShowAutocomplete(!initialData);
    }
  }, [isOpen, initialData]);

  const filteredExercises = useMemo(() => {
    if (!searchTerm) return [];
    const term = searchTerm.toLowerCase();
    return globalLibrary.filter((ex: GlobalExercise) =>
      ex.name.toLowerCase().includes(term) ||
      ex.muscleGroups.some((mg: string) => mg.toLowerCase().includes(term))
    ).slice(0, 10);
  }, [searchTerm, globalLibrary]);

  const handleInputChange = (field: string, value: any) => {
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
      toast({ variant: 'destructive', title: "Last Set Required", description: "Every exercise requires at least one set protocol." })
      return;
    }
    setExerciseData(
      produce(draft => {
        draft.sets.splice(index, 1);
      })
    );
  };

  const handleAutocompleteSelect = useCallback((selectedExercise: GlobalExercise) => {
    const stateToSet = getInitialExerciseState(selectedExercise);
    // Explicitly undefined ID as we are creating a NEW instance of this global exercise
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
      toast({ variant: 'destructive', title: 'Identity Required', description: 'Please name this exercise protocol.' });
      return;
    }
    if (exerciseData.sets.some(s => !String(s.targetReps).trim())) {
      toast({ variant: 'destructive', title: 'Volume Required', description: 'Each set needs a defined target.' });
      return;
    }

    const finalMuscleGroups = muscleGroupsInput.split(',').map(s => s.trim()).filter(s => s);

    // If we have a globalExerciseId, us that. If not, generate a custom ID.
    // However, for the PlanExercise structure, the 'id' is the unique instance ID.
    // 'globalExerciseId' is the reference.
    // If it's a custom exercise, we can use a convention like 'custom-TIMESTAMP' or similar.

    // We need to generate a unique ID for this PLAN EXERCISE instance
    const newInstanceId = initialData?.id || `inst-${Date.now()}-${Math.random().toString(36).substr(2, 5)}`;

    // Determine global reference ID
    const globalRefId = exerciseData.globalExerciseId || `custom-${exerciseData.name.toLowerCase().replace(/\s+/g, '-')}-${Date.now()}`;

    const exerciseToSave: PlanExercise = {
      id: newInstanceId,
      globalExerciseId: globalRefId,
      name: exerciseData.name,
      targetWeight: exerciseData.targetWeight,
      unit: exerciseData.unit,
      description: exerciseData.description,
      videoUrl: exerciseData.videoUrl,
      muscleGroups: finalMuscleGroups,
      notes: exerciseData.notes,
      sets: exerciseData.sets.map((s, index) => ({
        id: (s.id && s.id.startsWith('set-')) ? s.id : `set-${newInstanceId}-${index}`,
        targetReps: s.targetReps,
        targetWeight: s.targetWeight,
        unit: s.unit || exerciseData.unit || 'reps',
        exerciseId: newInstanceId,
      })),
    };
    onSave(exerciseToSave);
  };

  const isFormVisible = isEditing || exerciseData.name;

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl w-[95vw] h-[90vh] md:h-[80vh] flex flex-col glass-panel border-none rounded-[2rem] md:rounded-[2.5rem] overflow-hidden p-0 gap-0 shadow-2xl animate-in fade-in zoom-in-95 duration-300">
        <DialogHeader className="pt-8 pb-4 md:pt-10 md:pb-6 px-6 md:px-10 bg-white/5 border-b border-white/5">
          <DialogTitle className="text-2xl md:text-3xl font-black tracking-tight font-heading italic uppercase">
            {isEditing ? `Optimize Protocol` : 'Add Movement'}
          </DialogTitle>
          <DialogDescription className="text-muted-foreground font-medium uppercase tracking-[0.2em] text-[9px] md:text-[10px] opacity-50">
            {isEditing ? "Refining execution parameters" : "Search global database or architect custom metrics"}
          </DialogDescription>
        </DialogHeader>

        <div className="p-6 md:p-10 pb-4 relative flex-shrink-0 bg-white/[0.02]">
          <Label htmlFor="exerciseName" className="text-[9px] uppercase tracking-widest font-black opacity-30 mb-2 block">Movement Identity*</Label>
          <div className="relative group">
            <div className="relative">
              <Search className="absolute left-4 top-1/2 -translate-y-1/2 h-5 w-5 text-muted-foreground/30" />
              <Input
                id="exerciseName"
                value={searchTerm}
                autoComplete="off"
                className="h-12 md:h-14 bg-white/5 border-white/10 rounded-xl md:rounded-2xl pl-12 pr-4 md:pr-6 focus:ring-primary/50 focus:ring-1 focus:border-primary/50 transition-all text-base md:text-lg font-bold placeholder:font-medium placeholder:opacity-20"
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
                placeholder="Search exercises..."
              />
            </div>

            {showAutocomplete && !isEditing && (
              <div className="absolute z-50 w-full glass-panel border-white/10 rounded-xl md:rounded-2xl mt-2 max-h-60 md:max-h-72 overflow-y-auto shadow-2xl animate-in fade-in slide-in-from-top-2 duration-200">
                {filteredExercises.length > 0 ? (
                  <div className="p-1.5 space-y-1">
                    {filteredExercises.map((ex: GlobalExercise) => (
                      <div
                        key={ex.id}
                        className="px-4 py-3 md:px-6 md:py-4 hover:bg-primary/10 cursor-pointer rounded-lg md:rounded-xl transition-colors flex items-center justify-between group/item"
                        onMouseDown={() => handleAutocompleteSelect(ex)}
                      >
                        <div className="flex flex-col">
                          <span className="font-bold text-sm tracking-tight">{ex.name}</span>
                          <div className="flex gap-2 mt-1">
                            <Badge variant="outline" className="text-[10px] py-0 h-4 border-white/10 text-muted-foreground">{ex.category}</Badge>
                            {(ex.muscleGroups || []).slice(0, 2).map((mg: string) => (
                              <span key={mg} className="text-[10px] text-muted-foreground opacity-50">{mg}</span>
                            ))}
                          </div>
                        </div>
                        <PlusCircle className="h-4 w-4 text-primary opacity-0 group-hover/item:opacity-100 transition-opacity" />
                      </div>
                    ))}
                  </div>
                ) : searchTerm.length > 2 && (
                  <div className="p-1.5 border-t border-white/5">
                    <div
                      className="px-4 py-4 md:px-6 md:py-5 hover:bg-primary/20 cursor-pointer text-primary rounded-lg md:rounded-xl transition-all flex items-center gap-3 font-bold text-xs"
                      onMouseDown={handleCreateNewFromSearch}
                    >
                      <div className="w-8 h-8 rounded-lg bg-primary/20 flex items-center justify-center shrink-0">
                        <PlusCircle className="h-4 w-4" />
                      </div>
                      <span className="truncate">Initialize Custom: "{searchTerm}"</span>
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>

        {isFormVisible ? (
          <ScrollArea className="flex-grow">
            <div className="px-6 md:px-10 py-6 space-y-8 md:space-y-10 pb-12">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-6 md:gap-8">
                <div className="space-y-2">
                  <Label htmlFor="targetWeight" className="text-[9px] uppercase tracking-widest font-black opacity-30">Base Intensity</Label>
                  <Input id="targetWeight" value={exerciseData.targetWeight} onChange={(e) => handleInputChange('targetWeight', e.target.value)} placeholder="e.g., 80kg" className="bg-white/5 border-white/10 rounded-xl h-11 md:h-12 font-bold" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="defaultUnit" className="text-[9px] uppercase tracking-widest font-black opacity-30">Metric System</Label>
                  <Select value={exerciseData.unit} onValueChange={(value: 'reps' | 's' | 'min') => handleInputChange('unit', value)}>
                    <SelectTrigger id="defaultUnit" className="bg-white/5 border-white/10 rounded-xl h-11 md:h-12 font-bold focus:ring-primary/50"><SelectValue placeholder="Select unit" /></SelectTrigger>
                    <SelectContent className="glass-panel border-white/10 rounded-xl">
                      <SelectItem value="reps" className="hover:bg-primary/10">Reps (Capacity)</SelectItem>
                      <SelectItem value="s" className="hover:bg-primary/10">Seconds (Duration)</SelectItem>
                      <SelectItem value="min" className="hover:bg-primary/10">Minutes (Endurance)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="space-y-2">
                <Label htmlFor="muscleGroups" className="text-[9px] uppercase tracking-widest font-black opacity-30">Anatomical Focus</Label>
                <Input id="muscleGroups" value={muscleGroupsInput} onChange={handleMuscleGroupsChange} placeholder="e.g., Chest, Front Delts" className="bg-white/5 border-white/10 rounded-xl h-11 md:h-12 font-bold" />
              </div>

              <div className="space-y-2">
                <Label htmlFor="description" className="text-[9px] uppercase tracking-widest font-black opacity-30">Tactical Execution</Label>
                <Textarea id="description" value={exerciseData.description} onChange={(e) => handleInputChange('description', e.target.value)} placeholder="Technical cues or structural parameters..." rows={3} className="bg-white/5 border-white/10 rounded-xl md:rounded-2xl p-4 md:p-6 resize-none min-h-[100px] md:min-h-[120px] font-medium" />
              </div>

              <div className="space-y-6">
                <div className="flex items-center justify-between">
                  <Label className="text-[9px] uppercase tracking-widest font-black opacity-30">Set Architecture*</Label>
                  <span className="text-[9px] font-black text-primary px-2.5 py-0.5 rounded-md bg-primary/10 tracking-widest uppercase">Volume Def</span>
                </div>

                <div className="space-y-3">
                  {exerciseData.sets.map((set, index) => (
                    <div key={set.id || `temp-${index}`} className="group/set flex flex-col xs:flex-row items-stretch xs:items-end gap-3 md:gap-4 p-4 md:p-5 rounded-xl md:rounded-2xl bg-white/5 border border-white/5 hover:border-primary/10 transition-all duration-300">
                      <div className="flex items-center justify-between xs:justify-start xs:flex-col gap-2">
                        <div className="w-8 h-8 rounded-lg bg-white/5 flex items-center justify-center text-[10px] font-black text-foreground/40 shrink-0">
                          {index + 1}
                        </div>
                        <Button variant="ghost" size="icon" onClick={() => removeSet(index)} className="xs:hidden text-destructive h-8 w-8 rounded-lg hover:bg-destructive/10"><Trash2 className="h-3.5 w-3.5" /></Button>
                      </div>

                      <div className="grid grid-cols-2 gap-3 flex-grow">
                        <div className="space-y-1.5">
                          <Label htmlFor={`set-reps-${index}`} className="text-[8px] uppercase tracking-widest opacity-30 font-black">Target</Label>
                          <Input id={`set-reps-${index}`} value={set.targetReps} onChange={(e) => handleSetChange(index, 'targetReps', e.target.value)} placeholder="8-12" className="h-9 bg-transparent border-none rounded-none border-b border-white/10 focus:border-primary px-0 text-base md:text-lg font-black transition-all focus:ring-0" />
                        </div>
                        <div className="space-y-1.5">
                          <Label htmlFor={`set-weight-${index}`} className="text-[8px] uppercase tracking-widest opacity-30 font-black">Intensity</Label>
                          <Input id={`set-weight-${index}`} value={set.targetWeight} onChange={(e) => handleSetChange(index, 'targetWeight', e.target.value)} placeholder="Auto" className="h-9 bg-transparent border-none rounded-none border-b border-white/10 focus:border-primary px-0 text-base md:text-lg font-black transition-all focus:ring-0" />
                        </div>
                      </div>

                      <Button variant="ghost" size="icon" onClick={() => removeSet(index)} className="hidden xs:flex text-foreground/20 hover:text-destructive h-9 w-9 rounded-xl hover:bg-destructive/10 transition-colors shrink-0 mb-0.5"><Trash2 className="h-4 w-4" /></Button>
                    </div>
                  ))}

                  <Button type="button" variant="outline" onClick={addSet} className="w-full h-12 md:h-14 border-dashed border-white/10 hover:bg-white/5 rounded-xl md:rounded-2xl transition-all flex items-center gap-3 interactive-scale mt-4 group/add">
                    <PlusCircle className="h-4 w-4 md:h-5 md:w-5 text-primary group-hover/add:scale-110 transition-transform" />
                    <span className="text-[10px] font-black uppercase tracking-[0.2em]">Append Volume Set</span>
                  </Button>
                </div>
              </div>
            </div>
          </ScrollArea>
        ) : (
          <div className="flex-grow flex flex-col items-center justify-center text-muted-foreground p-10 md:p-20 text-center opacity-20">
            <Dumbbell className="h-12 w-12 md:h-16 md:w-16 mb-4 md:mb-6" />
            <p className="font-bold tracking-widest uppercase text-[10px]">Awaiting Architectural Definition</p>
          </div>
        )}

        <DialogFooter className="p-6 md:p-10 glass-panel border-t border-white/5 bg-white/5 flex flex-col xs:flex-row items-stretch gap-4">
          <Button type="button" variant="ghost" onClick={() => onOpenChange(false)} className="h-12 md:h-14 px-6 md:px-8 rounded-xl md:rounded-2xl hover:bg-white/5 text-[10px] font-black uppercase tracking-widest">Abort</Button>
          <Button
            type="button"
            onClick={handleSubmit}
            disabled={!exerciseData.name}
            className="h-12 md:h-14 px-8 md:px-10 rounded-xl md:rounded-2xl bg-primary hover:bg-primary/90 text-background text-[10px] font-black uppercase tracking-widest shadow-xl shadow-primary/20 flex-grow interactive-scale"
          >
            {isEditing ? 'Commit Evolution' : 'Finalize Inclusion'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
