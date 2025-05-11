'use client';

import type { SetData, LoggedSetData } from '@/types/workout';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Label } from '@/components/ui/label';
import { Check, Edit3, Dumbbell } from 'lucide-react';
import { useState } from 'react';

interface SetLoggerProps {
  setNumber: number;
  setData: SetData;
  loggedSetData?: LoggedSetData;
  onLogSet: (log: LoggedSetData) => void;
  exerciseUnit?: 'reps' | 's' | 'min';
  isSimpleLog?: boolean; // For exercises like conditioning, warmups etc.
}

export default function SetLogger({ 
  setNumber, 
  setData, 
  loggedSetData, 
  onLogSet, 
  exerciseUnit,
  isSimpleLog = false
}: SetLoggerProps) {
  const unitLabel = setData.unit || exerciseUnit || 'reps';
  const [currentReps, setCurrentReps] = useState<string>(loggedSetData?.reps?.toString() || '');
  const [currentWeight, setCurrentWeight] = useState<string>(loggedSetData?.weight?.toString() || '');
  const [isEditing, setIsEditing] = useState(!loggedSetData?.isCompleted);

  const handleLog = () => {
    onLogSet({ 
      reps: isSimpleLog ? setData.targetReps : currentReps, 
      weight: isSimpleLog ? setData.targetWeight : currentWeight, 
      isCompleted: true 
    });
    setIsEditing(false);
  };
  
  const handleEdit = () => {
    setIsEditing(true);
  }

  const handleMarkAsDone = () => {
     onLogSet({ reps: setData.targetReps, weight: setData.targetWeight, isCompleted: true });
     setIsEditing(false);
  }

  const handleMarkAsNotDone = () => {
    onLogSet({ reps: loggedSetData?.reps, weight: loggedSetData?.weight, isCompleted: false });
    setIsEditing(true);
  }


  if (isSimpleLog) {
    return (
      <div className="flex items-center justify-between p-3 border-t border-border/50">
        <div className="flex items-center gap-2">
          <span className="font-medium text-sm w-12">Set {setNumber}:</span>
          <span className="text-sm text-muted-foreground">{setData.targetReps} {setData.targetWeight && `(${setData.targetWeight})`}</span>
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


  if (!isEditing && loggedSetData?.isCompleted) {
    return (
      <div className="flex items-center justify-between p-3 border-t border-border/50 bg-secondary/30">
        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
          <span className="font-medium w-12">Set {setNumber}:</span>
          <span>Target: {setData.targetReps} {unitLabel} {setData.targetWeight && `(${setData.targetWeight || 'N/A'})`}</span>
          <span className="text-primary font-semibold">Logged: {loggedSetData.reps || 'N/A'} {unitLabel} {loggedSetData.weight && `(${loggedSetData.weight})`}</span>
        </div>
        <Button variant="ghost" size="icon" onClick={handleEdit} className="h-8 w-8">
          <Edit3 className="h-4 w-4" />
        </Button>
      </div>
    );
  }

  return (
    <div className="p-3 border-t border-border/50">
      <div className="flex items-end gap-3 mb-2">
        <Label htmlFor={`set-${setNumber}-reps`} className="w-12 pt-1 text-sm font-medium">
          Set {setNumber}
        </Label>
        <div className="flex-1">
          <Label htmlFor={`set-${setNumber}-reps`} className="text-xs text-muted-foreground">
            {unitLabel.charAt(0).toUpperCase() + unitLabel.slice(1)} (Target: {setData.targetReps})
          </Label>
          <Input
            id={`set-${setNumber}-reps`}
            type="text"
            placeholder={`${setData.targetReps}`}
            value={currentReps}
            onChange={(e) => setCurrentReps(e.target.value)}
            className="h-9 text-sm"
          />
        </div>
        { (setData.targetWeight !== undefined || unitLabel === 'reps') &&
          <div className="flex-1">
            <Label htmlFor={`set-${setNumber}-weight`} className="text-xs text-muted-foreground">
              Weight (Target: {setData.targetWeight || 'N/A'})
            </Label>
            <Input
              id={`set-${setNumber}-weight`}
              type="text"
              placeholder={setData.targetWeight || "N/A"}
              value={currentWeight}
              onChange={(e) => setCurrentWeight(e.target.value)}
              className="h-9 text-sm"
            />
          </div>
        }
        <Button onClick={handleLog} size="sm" className="h-9">
          <Check className="h-4 w-4" />
          <span className="sr-only">Log Set</span>
        </Button>
      </div>
    </div>
  );
}
