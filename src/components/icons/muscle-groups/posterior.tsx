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
      {/* Base Silhouette Outline */}
      <path
        d="M100,20 Q115,20 115,45 Q115,55 108,60 L108,75 Q130,75 145,85 Q160,95 160,120 L160,170 Q165,170 170,180 L180,240 Q182,250 175,250 L160,250 L155,185 Q150,175 145,180 L145,340 Q145,360 135,375 L135,390 L110,390 L105,340 Q105,330 100,330 Q95,330 95,340 L90,390 L65,390 L65,375 Q55,360 55,340 L55,180 Q50,175 45,185 L40,250 L25,250 Q18,250 20,240 L30,180 Q35,170 40,170 L40,120 Q40,95 55,85 Q70,75 92,75 L92,60 Q85,55 85,45 Q85,20 100,20 Z"
        className="fill-muted/20 stroke-muted-foreground/20 stroke-[1px]"
      />

      {/* Traps */}
      <g id="post-traps" className={getMuscleClass('Traps')} onClick={() => onMuscleClick('Traps')}>
        <path d="M100,75 L125,85 L120,115 L100,125 L80,115 L75,85 Z" />
      </g>

      {/* Rear Delts */}
      <g id="post-rear-delts" className={getMuscleClass('Rear Delts')} onClick={() => onMuscleClick('Rear Delts')}>
        <path d="M70,85 Q60,85 55,105 Q55,120 70,120 Z" />
        <path d="M130,85 Q140,85 145,105 Q145,120 130,120 Z" />
      </g>

      {/* Lats */}
      <g id="post-lats" className={getMuscleClass('Lats')} onClick={() => onMuscleClick('Lats')}>
        <path d="M80,125 Q65,135 70,195 L95,195 Q90,165 100,125 Z" />
        <path d="M120,125 Q135,135 130,195 L105,195 Q110,165 100,125 Z" />
      </g>

      {/* Upper Back */}
      <g id="post-upper-back" className={getMuscleClass('Upper Back')} onClick={() => onMuscleClick('Upper Back')}>
        <path d="M85,115 L115,115 L110,140 L90,140 Z" />
      </g>

      {/* Triceps */}
      <g id="post-triceps" className={getMuscleClass('Triceps')} onClick={() => onMuscleClick('Triceps')}>
        <path d="M50,110 Q42,135 48,165 L60,165 Q65,135 60,110 Z" />
        <path d="M150,110 Q158,135 152,165 L140,165 Q135,135 140,110 Z" />
      </g>

      {/* Forearms */}
      <g id="post-forearms" className={getMuscleClass('Forearms')} onClick={() => onMuscleClick('Forearms')}>
        <path d="M48,170 Q38,200 42,238 L58,238 Q63,200 63,170 Z" />
        <path d="M152,170 Q162,200 158,238 L142,238 Q137,200 137,170 Z" />
      </g>

      {/* Lower Back */}
      <g id="post-lower-back" className={getMuscleClass('Lower Back')} onClick={() => onMuscleClick('Lower Back')}>
        <path d="M85,195 L115,195 L110,225 L90,225 Z" />
      </g>

      {/* Glutes */}
      <g id="post-glutes" className={getMuscleClass('Glutes')} onClick={() => onMuscleClick('Glutes')}>
        <path d="M65,225 Q60,255 80,275 L100,275 Q100,250 100,225 Z" />
        <path d="M135,225 Q140,255 120,275 L100,275 Q100,250 100,225 Z" />
      </g>

      {/* Hamstrings */}
      <g id="post-hamstrings" className={getMuscleClass('Hamstrings')} onClick={() => onMuscleClick('Hamstrings')}>
        <path d="M70,275 Q65,310 75,355 L95,355 Q95,310 90,275 Z" />
        <path d="M130,275 Q135,310 125,355 L105,355 Q105,310 110,275 Z" />
      </g>

      {/* Calves */}
      <g id="post-calves" className={getMuscleClass('Calves')} onClick={() => onMuscleClick('Calves')}>
        <path d="M75,355 Q70,370 75,390 L85,390 Q90,370 85,355 Z" />
        <path d="M125,355 Q130,370 125,390 L115,390 Q110,370 115,355 Z" />
      </g>
    </svg>
  );
}
