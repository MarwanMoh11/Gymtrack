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
      viewBox="0 0 350 800"
      aria-label="Posterior view of muscle groups"
      {...props}
    >
        <g id="post-traps" className={getMuscleClass('Traps')} onClick={() => onMuscleClick('Traps')}>
            <path d="M198.2,143.4l-31.5,13.3l-34.9-13.3L130.6,128l37.7-10.6l31.5,13.3V143.4z"/>
        </g>
        <g id="post-upper-back" className={getMuscleClass('Upper Back')} onClick={() => onMuscleClick('Upper Back')}>
            <path d="M198.2,156.7v38.8h-79.6V156.7L130.6,145l37.7-10.6l31.5,13.3V156.7z"/>
        </g>
        <g id="post-lats" className={getMuscleClass('Lats')} onClick={() => onMuscleClick('Lats')}>
            <path d="M216.4,195.5v72.2h-18.9v-60h-79.6v60h-18.9V195.5h117.4z"/>
        </g>
        <g id="post-rear-delts" className={getMuscleClass('Rear Delts')} onClick={() => onMuscleClick('Rear Delts')}>
            <path d="M231.6,156.7l-14.5,38.8h-18.9l14.5-38.8H231.6z M102.8,156.7l14.5,38.8h18.9l-14.5-38.8H102.8z"/>
        </g>
        <g id="post-triceps" className={getMuscleClass('Triceps')} onClick={() => onMuscleClick('Triceps')}>
            <path d="M 231.6,195.5v32.2h-14.5v12.2h-8.9V212h-9.9v-16.5H231.6z"/>
            <path d="M 102.8,195.5v32.2h14.5v12.2h8.9V212h9.9v-16.5H102.8z"/>
        </g>
        <g id="post-forearms" className={getMuscleClass('Forearms')} onClick={() => onMuscleClick('Forearms')}>
            <path d="M 231.6,239.9v35.4h-10.9v10.1h-10.9v-11.2h-11.9v-34.3H231.6z"/>
            <path d="M 102.8,239.9v35.4h10.9v10.1h10.9v-11.2h11.9v-34.3H102.8z"/>
        </g>
        <g id="post-lower-back" className={getMuscleClass('Lower Back')} onClick={() => onMuscleClick('Lower Back')}>
            <path d="M186.5,267.7v41.8h-74.8V267.7H186.5z"/>
        </g>
        <g id="post-glutes" className={getMuscleClass('Glutes')} onClick={() => onMuscleClick('Glutes')}>
            <path d="M206.5,309.5v52.2h-38.8v-52.2h-24.8v52.2h-38.8v-52.2H206.5z"/>
        </g>
        <g id="post-hamstrings" className={getMuscleClass('Hamstrings')} onClick={() => onMuscleClick('Hamstrings')}>
            <path d="M186.5,361.7v100h-24.8v-100h-24.8v100h-24.8v-100H186.5z"/>
        </g>
        <g id="post-calves" className={getMuscleClass('Calves')} onClick={() => onMuscleClick('Calves')}>
            <path d="M186.5,461.7v60h-24.8v-60h-24.8v60h-24.8v-60H186.5z"/>
        </g>
    </svg>
  );
}
