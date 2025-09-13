// src/components/icons/muscle-groups/posterior.tsx
import React, { SVGProps } from 'react';
import { cn } from '@/lib/utils';

type MuscleViewProps = SVGProps<SVGSVGElement> & {
  onMuscleClick: (muscle: string) => void;
  getMuscleClass: (muscleName: string) => string;
};

export default function PosteriorView({ onMuscleClick, getMuscleClass, ...props }: MuscleViewProps) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 200 400"
      aria-label="Posterior view of muscle groups"
      {...props}
      shapeRendering="crispEdges"
    >
      {/* Head */}
      <rect x="80" y="20" width="40" height="40" className="fill-muted-foreground/20" />
      
      {/* Neck */}
      <rect x="90" y="60" width="20" height="10" className="fill-muted-foreground/20" />

      {/* Traps */}
      <g id="post-traps" className={getMuscleClass('Traps')} onClick={() => onMuscleClick('Traps')}>
        <rect x="70" y="70" width="60" height="30" />
      </g>

      {/* Rear Delts */}
      <g id="post-rear-delts" className={getMuscleClass('Rear Delts')} onClick={() => onMuscleClick('Rear Delts')}>
        <rect x="50" y="70" width="20" height="20" />
        <rect x="130" y="70" width="20" height="20" />
      </g>
      
      {/* Lats & Upper Back */}
      <g id="post-lats" className={getMuscleClass('Lats')} onClick={() => onMuscleClick('Lats')}>
        <rect x="60" y="100" width="80" height="60" />
      </g>
      <g id="post-upper-back" className={getMuscleClass('Upper Back')} onClick={() => onMuscleClick('Upper Back')}>
        <rect x="80" y="100" width="40" height="30" />
      </g>

      {/* Triceps */}
      <g id="post-triceps" className={getMuscleClass('Triceps')} onClick={() => onMuscleClick('Triceps')}>
        <rect x="50" y="90" width="20" height="50" />
        <rect x="130" y="90" width="20" height="50" />
      </g>

      {/* Forearms */}
      <g id="post-forearms" className={getMuscleClass('Forearms')} onClick={() => onMuscleClick('Forearms')}>
        <rect x="50" y="140" width="10" height="60" />
        <rect x="140" y="140" width="10" height="60" />
      </g>

      {/* Lower Back */}
      <g id="post-lower-back" className={getMuscleClass('Lower Back')} onClick={() => onMuscleClick('Lower Back')}>
        <rect x="80" y="160" width="40" height="30" />
      </g>

      {/* Glutes */}
      <g id="post-glutes" className={getMuscleClass('Glutes')} onClick={() => onMuscleClick('Glutes')}>
        <rect x="60" y="190" width="80" height="40" />
      </g>

      {/* Hamstrings */}
      <g id="post-hamstrings" className={getMuscleClass('Hamstrings')} onClick={() => onMuscleClick('Hamstrings')}>
        <rect x="60" y="230" width="30" height="60" />
        <rect x="110" y="230" width="30" height="60" />
      </g>

      {/* Calves */}
      <g id="post-calves" className={getMuscleClass('Calves')} onClick={() => onMuscleClick('Calves')}>
        <rect x="60" y="290" width="30" height="80" />
        <rect x="110" y="290" width="30" height="80" />
      </g>
    </svg>
  );
}
