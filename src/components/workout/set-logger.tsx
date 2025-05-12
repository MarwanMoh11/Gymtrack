
'use client';

import type { SetData, LoggedSetData } from '@/types/workout';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Check, Edit3, Plus, Minus, Dumbbell } from 'lucide-react';
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
  
  // State for the reps input
  const [currentReps, setCurrentReps] = useState<string>(() => {
    if (loggedSetData?.reps !== undefined) return String(loggedSetData.reps);
    if (previousLoggedReps !== undefined) return String(previousLoggedReps);
    return ''; // Start empty if no prior data
  });

  // State for editing mode
  const [isEditing, setIsEditing] = useState(isEditingInitially);

  // Effect to update editing state if isEditingInitially changes (e.g., after weight reset)
  useEffect(() => {
    setIsEditing(isEditingInitially);
    if (isEditingInitially && loggedSetData?.reps !== undefined) {
        setCurrentReps(String(loggedSetData.reps)); // Ensure input reflects reset value
    } else if (isEditingInitially) {
        setCurrentReps(previousLoggedReps !== undefined ? String(previousLoggedReps) : '');
    }
  }, [isEditingInitially, loggedSetData?.reps, previousLoggedReps]);

   // Effect to reset currentReps if loggedData is cleared externally (e.g., day log cleared)
   useEffect(() => {
    if (!loggedSetData && isEditing) {
       setCurrentReps(previousLoggedReps !== undefined ? String(previousLoggedReps) : '');
    }
   }, [loggedSetData, isEditing, previousLoggedReps]);


  const handleLog = () => {
    // Log with current reps and the effective target weight for the exercise
    onLogSet({
      reps: currentReps || setData.targetReps, // Use target if input is empty
      weight: effectiveTargetWeight || setData.targetWeight, // Use the overall exercise target weight
      isCompleted: true
    });
    setIsEditing(false);
  };

  const handleEdit = () => {
    setIsEditing(true);
  }

  const handleMarkAsDone = () => {
     onLogSet({ 
        reps: setData.targetReps, 
        weight: effectiveTargetWeight || setData.targetWeight, 
        isCompleted: true 
    });
     setIsEditing(false);
  }

  const handleMarkAsNotDone = () => {
    onLogSet({ reps: loggedSetData?.reps, weight: loggedSetData?.weight, isCompleted: false });
    setIsEditing(true);
    // Ensure currentReps reflects the previously logged value when re-editing
    setCurrentReps(loggedSetData?.reps !== undefined ? String(loggedSetData.reps) : (previousLoggedReps !== undefined ? String(previousLoggedReps) : ''));
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
          {/* Show logged reps and the weight used for the whole exercise during this set */}
          <span className="text-primary font-semibold flex items-center">
            Logged: {loggedSetData.reps || 'N/A'} {unitLabel}
            {loggedSetData.weight && (
                <span className='ml-2 flex items-center text-xs text-muted-foreground'>
                    <Dumbbell className='h-3 w-3 mr-1'/> ({loggedSetData.weight})
                </span>
            )}
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
              type="number" // Use number type for better mobile input
              inputMode="numeric" // Hint for numeric keyboard
              pattern="[0-9]*" // Pattern for numeric input
              placeholder={`${setData.targetReps}`}
              value={currentReps}
              onChange={(e) => setCurrentReps(e.target.value.replace(/[^0-9]/g, ''))} // Allow only numbers
              className="h-9 text-sm text-center appearance-none w-16" // Adjust width as needed
              style={{ MozAppearance: 'textfield' }} // Hide spinners in Firefox
            />
             <Button onClick={incrementReps} size="icon" variant="outline" className="h-9 w-9 shrink-0">
              <Plus className="h-4 w-4" />
              <span className="sr-only">Increment reps</span>
            </Button>
          </div>
        </div>
        {/* Weight input removed from here */}
        <Button onClick={handleLog} size="sm" className="h-9 shrink-0 self-end">
          <Check className="h-4 w-4" />
          <span className="sr-only sm:not-sr-only sm:ml-1">Log</span>
        </Button>
      </div>
      {/* Display target weight hint if applicable */}
      {(effectiveTargetWeight || setData.targetWeight) && unitLabel === 'reps' && (
          <p className='text-xs text-muted-foreground text-right mt-1 pr-12 sm:pr-16'>
             Weight: {effectiveTargetWeight || setData.targetWeight}
          </p>
      )}
    </div>
  );
}
