
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

export const getVolumeColor = (volume: number, maxVolume: number): string => {
  if (volume === 0) return 'fill-white/[0.03] hover:fill-white/[0.08] stroke-white/5';
  if (maxVolume === 0) return 'fill-primary/20 hover:fill-primary/30 stroke-primary/20';

  const ratio = volume / maxVolume;
  if (ratio < 0.33) return 'fill-primary/20 hover:fill-primary/30 stroke-primary/30'; // Low volume
  if (ratio < 0.66) return 'fill-primary/50 hover:fill-primary/60 stroke-primary/50'; // Medium volume
  return 'fill-primary hover:fill-primary/90 stroke-primary'; // High volume
};

export default function MuscleHeatmap({ muscleVolumes, onMuscleClick, selectedMuscle }: MuscleHeatmapProps) {
  const maxVolume = React.useMemo(() => Math.max(1, ...Object.values(muscleVolumes)), [muscleVolumes]);

  const muscleGroups = {
    'Chest': ['Chest', 'Pectoralis Major', 'Upper Pectoralis', 'Lower Pectoralis'],
    'Shoulders': ['Shoulders', 'Deltoids', 'Anterior Deltoids', 'All three Deltoid heads', 'Lateral Deltoids'],
    'Biceps': ['Biceps', 'Biceps Brachii', 'Brachialis'],
    'Abs': ['Abs', 'Rectus Abdominis', 'Transverse Abdominis', 'Lower Rectus Abdominis', 'Core'],
    'Obliques': ['Obliques'],
    'Quads': ['Quadriceps', 'Quads'],
    'Hip Adductors': ['Hip Adductors', 'Groin', 'Adductors'],
    'Serratus Anterior': ['Serratus Anterior'],
    'Hip Flexors': ['Hip Flexors'],

    'Traps': ['Traps', 'Trapezius', 'Upper Trapezius'],
    'Upper Back': ['Upper Back', 'Rhomboids'],
    'Lats': ['Lats', 'Latissimus Dorsi'],
    'Lower Back': ['Lower Back', 'Erector Spinae'],
    'Glutes': ['Glutes'],
    'Hamstrings': ['Hamstrings'],
    'Calves': ['Calves', 'Gastrocnemius', 'Soleus'],
    'Triceps': ['Triceps', 'Triceps Brachii'],
    'Forearms': ['Forearms', 'Forearm Flexors', 'Forearm Extensors', 'Brachioradialis'],
    'Rear Delts': ['Posterior Deltoids', 'Rear Delts']
  };

  const aggregatedVolumes: { [key: string]: number } = React.useMemo(() => {
    const volumes: { [key: string]: number } = {};
    for (const group in muscleGroups) {
      volumes[group] = (muscleGroups[group as keyof typeof muscleGroups] as string[]).reduce((acc, muscle) => acc + (muscleVolumes[muscle] || 0), 0);
    }
    return volumes;
  }, [muscleVolumes]);

  const maxAggregatedVolume = Math.max(1, ...Object.values(aggregatedVolumes));
  const selectedVolume = selectedMuscle ? aggregatedVolumes[selectedMuscle] : null;

  return (
    <div className="w-full grid grid-cols-1 lg:grid-cols-12 gap-8 items-start">
      {/* Left Column: Visualizers */}
      <div className="lg:col-span-8 flex flex-col gap-10">
        <div className="grid grid-cols-2 gap-4 sm:gap-12">
          <div className="flex flex-col items-center group">
            <div className="relative w-full aspect-[1/2] max-w-[260px] p-6 rounded-[2.5rem] bg-white/[0.02] border border-white/5 transition-all duration-700 overflow-hidden group-hover:bg-white/[0.04] group-hover:border-primary/20">
              <div className="absolute inset-0 bg-gradient-to-b from-primary/5 via-transparent to-transparent opacity-50" />
              <AnteriorView
                onMuscleClick={onMuscleClick}
                className="w-full h-full relative z-10 drop-shadow-[0_0_15px_rgba(0,0,0,0.5)]"
                getMuscleClass={(muscleName) =>
                  cn(
                    'transition-all duration-500 cursor-pointer',
                    getVolumeColor(aggregatedVolumes[muscleName] || 0, maxAggregatedVolume),
                    selectedMuscle === muscleName ? 'stroke-primary stroke-[2px] drop-shadow-[0_0_12px_rgba(var(--primary),0.8)]' : 'stroke-white/5'
                  )
                }
              />
              <div className="absolute bottom-6 left-0 right-0 text-center">
                <span className="text-[9px] uppercase tracking-[0.3em] text-muted-foreground/30 font-black">Front Matrix</span>
              </div>
            </div>
          </div>

          <div className="flex flex-col items-center group">
            <div className="relative w-full aspect-[1/2] max-w-[260px] p-6 rounded-[2.5rem] bg-white/[0.02] border border-white/5 transition-all duration-700 overflow-hidden group-hover:bg-white/[0.04] group-hover:border-primary/20">
              <div className="absolute inset-0 bg-gradient-to-b from-primary/5 via-transparent to-transparent opacity-50" />
              <PosteriorView
                onMuscleClick={onMuscleClick}
                className="w-full h-full relative z-10 drop-shadow-[0_0_15px_rgba(0,0,0,0.5)]"
                getMuscleClass={(muscleName) =>
                  cn(
                    'transition-all duration-500 cursor-pointer',
                    getVolumeColor(aggregatedVolumes[muscleName] || 0, maxAggregatedVolume),
                    selectedMuscle === muscleName ? 'stroke-primary stroke-[2px] drop-shadow-[0_0_12px_rgba(var(--primary),0.8)]' : 'stroke-white/5'
                  )
                }
              />
              <div className="absolute bottom-6 left-0 right-0 text-center">
                <span className="text-[9px] uppercase tracking-[0.3em] text-muted-foreground/30 font-black">Back Matrix</span>
              </div>
            </div>
          </div>
        </div>

        {/* Legend: Premium Style */}
        <div className="px-12 flex flex-col gap-4">
          <div className="flex justify-between text-[9px] font-black uppercase tracking-[0.2em] text-muted-foreground/40">
            <span>Latent Potential</span>
            <span>Hypertrophic Peak</span>
          </div>
          <div className="h-1.5 w-full rounded-full bg-white/5 relative overflow-hidden">
            <div className="absolute inset-0 bg-gradient-to-r from-primary/5 via-primary/40 to-primary shadow-[0_0_20px_rgba(var(--primary),0.3)]" />
          </div>
        </div>
      </div>

      {/* Right Column: Analytics Card */}
      <div className="lg:col-span-4 sticky top-6">
        <div className="p-8 rounded-[2rem] bg-white/[0.03] border border-white/10 backdrop-blur-2xl space-y-8 shadow-2xl relative overflow-hidden group">
          <div className="absolute -top-24 -right-24 w-48 h-48 bg-primary/10 rounded-full blur-[80px] transition-all duration-1000 group-hover:bg-primary/20" />

          <div className="space-y-2 relative z-10">
            <h4 className="text-[10px] font-black uppercase tracking-[0.25em] text-primary/60">Biometric Analysis</h4>
            <p className="text-xs text-muted-foreground leading-relaxed font-medium">
              Select a region on the anatomical model to analyze neuromuscular load and adaptation progress.
            </p>
          </div>

          <div className="h-px bg-white/5 w-full relative z-10" />

          {selectedMuscle ? (
            <div className="animate-in fade-in slide-in-from-right-4 duration-500 space-y-8 relative z-10">
              <div className="flex justify-between items-start">
                <div>
                  <h2 className="text-3xl font-black text-white tracking-tighter">{selectedMuscle}</h2>
                  <div className="flex items-center gap-2 mt-1">
                    <div className="w-1.5 h-1.5 rounded-full bg-primary animate-pulse" />
                    <p className="text-[10px] text-primary font-black uppercase tracking-widest">Active Focus</p>
                  </div>
                </div>
                <div className="text-right">
                  <span className="text-3xl font-mono font-bold text-primary">{Math.round((selectedVolume || 0) / maxAggregatedVolume * 100)}%</span>
                  <p className="text-[9px] text-muted-foreground font-black uppercase tracking-widest">Load Factor</p>
                </div>
              </div>

              <div className="space-y-3">
                <div className="flex justify-between text-[10px] uppercase tracking-[0.15em] font-black text-muted-foreground/60">
                  <span>Adaptation Status</span>
                  <span className="text-white">{selectedVolume} Units</span>
                </div>
                <div className="h-4 w-full bg-white/5 rounded-full overflow-hidden border border-white/5 p-0.5">
                  <div
                    className="h-full bg-primary rounded-full transition-all duration-1000 ease-out shadow-[0_0_20px_rgba(var(--primary),0.4)]"
                    style={{ width: `${Math.max(8, (selectedVolume || 0) / maxAggregatedVolume * 100)}%` }}
                  />
                </div>
              </div>

              <div className="p-5 rounded-2xl bg-white/[0.02] border border-white/5 relative group/item">
                <div className="absolute left-0 top-1/2 -translate-y-1/2 w-1 h-3/4 bg-primary/40 rounded-r-full" />
                <p className="text-xs text-muted-foreground leading-relaxed font-medium pl-2">
                  {selectedVolume === 0
                    ? `System indicates zero load for the ${selectedMuscle}. Recommend immediate integration of compound stimuli.`
                    : (selectedVolume || 0) / maxAggregatedVolume > 0.8
                      ? `${selectedMuscle} has reached peak operational capacity. Physiological ceiling detected. Prioritize neural recovery.`
                      : `${selectedMuscle} is in an optimal hypertrophic phase. Volume-to-recovery ratio is currently efficient.`}
                </p>
              </div>
            </div>
          ) : (
            <div className="py-20 flex flex-col items-center text-center gap-6 opacity-40 animate-pulse relative z-10">
              <div className="w-16 h-16 rounded-full border-2 border-dashed border-primary/30 flex items-center justify-center">
                <div className="w-8 h-8 rounded-full bg-primary/20" />
              </div>
              <p className="text-[10px] font-black uppercase tracking-[0.2em] max-w-[200px] leading-loose">
                Awaiting anatomical selection for biometric readout
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
