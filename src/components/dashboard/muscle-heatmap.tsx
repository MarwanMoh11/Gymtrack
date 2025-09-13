// src/components/dashboard/muscle-heatmap.tsx
import React from 'react';
import AnteriorView from '../icons/muscle-groups/anterior';
import PosteriorView from '../icons/muscle-groups/posterior';
import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';

interface MuscleHeatmapProps {
  muscleVolumes: { [key: string]: number };
  onMuscleClick: (muscle: string) => void;
  selectedMuscle: string | null;
}

const getVolumeColor = (volume: number, maxVolume: number): string => {
  if (volume === 0) return 'fill-muted-foreground/10 hover:fill-muted-foreground/20';
  if (maxVolume === 0) return 'fill-green-500/50 hover:fill-green-500/70'; // Should not happen if volume > 0

  const ratio = volume / maxVolume;
  if (ratio < 0.33) return 'fill-green-500/50 hover:fill-green-500/70'; // Low volume
  if (ratio < 0.66) return 'fill-yellow-500/50 hover:fill-yellow-500/70'; // Medium volume
  return 'fill-red-500/50 hover:fill-red-500/70'; // High volume
};

export default function MuscleHeatmap({ muscleVolumes, onMuscleClick, selectedMuscle }: MuscleHeatmapProps) {
  const maxVolume = React.useMemo(() => Math.max(1, ...Object.values(muscleVolumes)), [muscleVolumes]);

  const muscleGroups = {
    // Anterior
    'Chest': ['Pectoralis Major', 'Upper Pectoralis', 'Lower Pectoralis'],
    'Shoulders': ['Deltoids', 'Anterior Deltoids', 'Lateral Deltoids'],
    'Biceps': ['Biceps', 'Biceps Brachii'],
    'Abs': ['Rectus Abdominis', 'Transverse Abdominis', 'Lower Rectus Abdominis'],
    'Obliques': ['Obliques'],
    'Quads': ['Quadriceps'],
    'Hip Adductors': ['Hip Adductors', 'Groin'],
    // Posterior
    'Traps': ['Trapezius', 'Upper Trapezius'],
    'Upper Back': ['Rhomboids'],
    'Lats': ['Latissimus Dorsi'],
    'Lower Back': ['Erector Spinae'],
    'Glutes': ['Glutes'],
    'Hamstrings': ['Hamstrings'],
    'Calves': ['Calves', 'Gastrocnemius', 'Soleus'],
    'Triceps': ['Triceps', 'Triceps Brachii'],
    'Forearms': ['Forearms', 'Forearm Flexors', 'Forearm Extensors', 'Brachialis', 'Brachioradialis'],
    'Rear Delts': ['Posterior Deltoids']
  };

  const aggregatedVolumes: { [key: string]: number } = {};
  for (const group in muscleGroups) {
    aggregatedVolumes[group] = (muscleGroups[group as keyof typeof muscleGroups] as string[]).reduce((acc, muscle) => acc + (muscleVolumes[muscle] || 0), 0);
  }

  const maxAggregatedVolume = Math.max(1, ...Object.values(aggregatedVolumes));

  return (
    <div className="w-full">
      <div className="flex justify-center items-center gap-4 mb-4">
        <Badge variant="outline" className="border-green-500/50 text-green-500">Low</Badge>
        <Badge variant="outline" className="border-yellow-500/50 text-yellow-500">Medium</Badge>
        <Badge variant="outline" className="border-red-500/50 text-red-500">High</Badge>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        <div className="flex flex-col items-center">
          <h3 className="font-semibold text-center mb-2">Anterior View</h3>
          <AnteriorView
            onMuscleClick={onMuscleClick}
            getMuscleClass={(muscleName) => 
                cn(
                    'transition-all duration-200 cursor-pointer',
                    getVolumeColor(aggregatedVolumes[muscleName] || 0, maxAggregatedVolume),
                    selectedMuscle === muscleName ? 'stroke-primary stroke-[3px]' : 'stroke-foreground/50'
                )
            }
          />
        </div>
        <div className="flex flex-col items-center">
          <h3 className="font-semibold text-center mb-2">Posterior View</h3>
          <PosteriorView
             onMuscleClick={onMuscleClick}
             getMuscleClass={(muscleName) => 
                cn(
                    'transition-all duration-200 cursor-pointer',
                    getVolumeColor(aggregatedVolumes[muscleName] || 0, maxAggregatedVolume),
                    selectedMuscle === muscleName ? 'stroke-primary stroke-[3px]' : 'stroke-foreground/50'
                )
            }
          />
        </div>
      </div>
    </div>
  );
}