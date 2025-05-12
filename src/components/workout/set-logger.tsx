
'use client';

import type { SetData, LoggedSetData } from '@/types/workout';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Check, Edit3, Plus, Minus } from 'lucide-react'; // Removed Dumbbell
import { useState, useEffect } from 'react';
import { cn } from '@/lib/utils';

interface SetLoggerProps {
  setNumber: number;
  setData: SetData; // Includes target reps/weight for the set definition
  loggedSetData?: LoggedSetData; // Data logged specifically for this set instance
  previousLoggedReps?: string | number; // Reps logged in the previous set of this session
  effectiveTargetWeight?: string; // The weight planned for this exercise today
  onLogSet: (log: LoggedSetData) => void;
  exerciseUnit?: 'reps' | 's' | 'min';
  isSimpleLog?: boolean; // For exercises like conditioning, warmups etc.
  isEditingInitially?: boolean; // Control initial edit state, e.g., after weight change
}

export default function SetLogger({
  setNumber,
  setData,
  loggedSetData,
  previousLoggedReps,
  effectiveTargetWeight,
  onLogSet,
  exerciseUnit,
  isSimpleLog = false,
  isEditingInitially = !loggedSetData?.isCompleted,
}: SetLoggerProps) {
  const unitLabel = setData.unit || exerciseUnit || 'reps';

  // Initialize with previous logged reps if editing and no current log, otherwise use current log or target
  const getInitialReps = () => {
    if (loggedSetData?.reps !== undefined) return String(loggedSetData.reps);
    if (isEditingInitially && previousLoggedReps !== undefined) return String(previousLoggedReps);
    return ''; // Default to empty if nothing else applies
  };

  const [currentReps, setCurrentReps] = useState<string>(getInitialReps);
  const [isEditing, setIsEditing] = useState(isEditingInitially);

  // Effect to update editing state and reps if isEditingInitially changes
   useEffect(() => {
    setIsEditing(isEditingInitially);
    // When forced into editing (e.g., weight change), reset input based on priority
    if (isEditingInitially) {
        if (loggedSetData?.reps !== undefined) {
           setCurrentReps(String(loggedSetData.reps));
        } else if (previousLoggedReps !== undefined) {
           setCurrentReps(String(previousLoggedReps));
        } else {
           setCurrentReps(''); // Fallback to empty
        }
    }
   }, [isEditingInitially, loggedSetData?.reps, previousLoggedReps]);

   // Effect to reset currentReps if loggedData is cleared externally
   useEffect(() => {
    if (!loggedSetData && isEditing) {
       setCurrentReps(previousLoggedReps !== undefined ? String(previousLoggedReps) : '');
    }
   }, [loggedSetData, isEditing, previousLoggedReps]);


  const handleLog = () => {
    // Log with current reps OR previous logged reps if input is empty, fallback to target
    const repsToLog = currentReps || (previousLoggedReps !== undefined ? String(previousLoggedReps) : setData.targetReps);
    onLogSet({
      reps: repsToLog,
      weight: effectiveTargetWeight || setData.targetWeight, // Use the overall exercise target weight
      isCompleted: true
    });
    setIsEditing(false);
  };

  const handleEdit = () => {
    setIsEditing(true);
    // Set input to the last logged value when starting edit
    setCurrentReps(loggedSetData?.reps !== undefined ? String(loggedSetData.reps) : '');
  }

  const handleMarkAsDone = () => {
     onLogSet({
        reps: setData.targetReps, // Use target reps when simply marking done
        weight: effectiveTargetWeight || setData.targetWeight,
        isCompleted: true
    });
     setIsEditing(false);
  }

  const handleMarkAsNotDone = () => {
    onLogSet({ reps: loggedSetData?.reps, weight: loggedSetData?.weight, isCompleted: false });
    setIsEditing(true);
    // Reset input to previously logged value or empty
    setCurrentReps(loggedSetData?.reps !== undefined ? String(loggedSetData.reps) : '');
  }

  const incrementReps = () => {
    setCurrentReps(prev => String(Number(prev || 0) + 1));
  };

  const decrementReps = () => {
    setCurrentReps(prev => String(Math.max(0, Number(prev || 0) - 1)));
  };


  if (isSimpleLog) {
    // Simplified view for activities, warmups etc.
    return (
      <div className="flex items-center justify-between p-3 border-t border-border/50">
        <div className="flex items-center gap-2">
          <span className="font-medium text-sm w-12">Set {setNumber}:</span>
          <span className="text-sm text-muted-foreground">{setData.targetReps} {setData.targetWeight ? `(${setData.targetWeight})` : ''}</span>
        </div>
        {loggedSetData?.isCompleted ? (
           <Button variant="ghost" size="sm" onClick={handleMarkAsNotDone} className="text-muted-foreground hover:text-foreground">
             <Check className="mr-1 h-4 w-4 text-primary" /> Done
           </Button>
        ) : (
          <Button variant="outline" size="sm" onClick={handleMarkAsDone}>
            Mark as Done
          </Button>
        )}
      </div>
    );
  }

  // View for completed sets
  if (!isEditing && loggedSetData?.isCompleted) {
    return (
      <div className="flex items-center justify-between p-3 border-t border-border/50 bg-secondary/30">
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
          <span className="font-medium w-12">Set {setNumber}:</span>
          <span>Target: {setData.targetReps} {unitLabel}</span>
          <span className="text-primary font-semibold flex items-center">
            Logged: {loggedSetData.reps ?? 'N/A'} {unitLabel}
            {/* Weight display removed from here */}
            </span>
        </div>
        <Button variant="ghost" size="icon" onClick={handleEdit} className="h-8 w-8">
          <Edit3 className="h-4 w-4" />
        </Button>
      </div>
    );
  }

  // View for editing/logging sets
  return (
    <div className="p-3 border-t border-border/50">
      <div className="flex items-end gap-2 sm:gap-3">
        <Label htmlFor={`set-${setNumber}-reps`} className="w-12 pt-1 text-sm font-medium shrink-0">
          Set {setNumber}
        </Label>
        <div className="flex-1">
          <Label htmlFor={`set-${setNumber}-reps`} className="text-xs text-muted-foreground">
            {unitLabel.charAt(0).toUpperCase() + unitLabel.slice(1)} (Target: {setData.targetReps})
          </Label>
          <div className="flex items-center gap-1 mt-1">
             <Button onClick={decrementReps} size="icon" variant="outline" className="h-9 w-9 shrink-0">
              <Minus className="h-4 w-4" />
              <span className="sr-only">Decrement reps</span>
            </Button>
            <Input
              id={`set-${setNumber}-reps`}
              type="number"
              inputMode="numeric"
              pattern="[0-9]*"
              // Use previous LOGGED reps as placeholder if available and editing, otherwise target
              placeholder={`${loggedSetData?.reps !== undefined ? loggedSetData.reps : (previousLoggedReps !== undefined ? previousLoggedReps : setData.targetReps)}`}
              value={currentReps}
              onChange={(e) => setCurrentReps(e.target.value.replace(/[^0-9]/g, ''))}
              className="h-9 text-lg font-semibold text-center appearance-none w-16 flex-shrink-0" // Larger text, fixed width
              style={{ MozAppearance: 'textfield' }} // Hide spinners in Firefox
            />
             <Button onClick={incrementReps} size="icon" variant="outline" className="h-9 w-9 shrink-0">
              <Plus className="h-4 w-4" />
              <span className="sr-only">Increment reps</span>
            </Button>
          </div>
        </div>
        {/* Weight input removed */}
        <Button onClick={handleLog} size="sm" className="h-9 shrink-0 self-end">
          <Check className="h-4 w-4" />
          <span className="sr-only sm:not-sr-only sm:ml-1">Log</span>
        </Button>
      </div>
    </div>
  );
}
