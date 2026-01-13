// src/components/icons/muscle-groups/anterior.tsx
import React, { SVGProps } from 'react';
import { cn } from '@/lib/utils';

type MuscleViewProps = SVGProps<SVGSVGElement> & {
  onMuscleClick: (muscle: string) => void;
  getMuscleClass: (muscleName: string) => string;
};

export default function AnteriorView({ onMuscleClick, getMuscleClass, ...props }: MuscleViewProps) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 200 400"
      aria-label="Anterior view of muscle groups"
      {...props}
      shapeRendering="crispEdges"
    >
      {/* Base Silhouette Outline */}
      <path
        d="M100,20 Q115,20 115,40 Q115,55 108,60 L108,75 Q130,75 145,85 Q160,95 160,120 L160,170 Q165,170 170,180 L180,240 Q182,250 175,250 L160,250 L155,185 Q150,175 145,180 L145,340 Q145,360 135,375 L135,390 L110,390 L105,340 Q105,330 100,330 Q95,330 95,340 L90,390 L65,390 L65,375 Q55,360 55,340 L55,180 Q50,175 45,185 L40,250 L25,250 Q18,250 20,240 L30,180 Q35,170 40,170 L40,120 Q40,95 55,85 Q70,75 92,75 L92,60 Q85,55 85,40 Q85,20 100,20 Z"
        className="fill-muted/20 stroke-muted-foreground/20 stroke-[1px]"
      />

      {/* Shoulders (Deltoids) */}
      <g id="ant-shoulders" className={getMuscleClass('Shoulders')} onClick={() => onMuscleClick('Shoulders')}>
        <path d="M65,85 Q55,85 50,105 Q50,125 65,125 Q70,115 75,100 Z" />
        <path d="M135,85 Q145,85 150,105 Q150,125 135,125 Q130,115 125,100 Z" />
      </g>

      {/* Chest (Pectorals) */}
      <g id="ant-chest" className={getMuscleClass('Chest')} onClick={() => onMuscleClick('Chest')}>
        <path d="M100,100 L80,105 Q75,135 100,150 Q125,135 120,105 Z" />
      </g>

      {/* Biceps */}
      <g id="ant-biceps" className={getMuscleClass('Biceps')} onClick={() => onMuscleClick('Biceps')}>
        <path d="M52,125 Q45,145 50,165 L65,165 Q68,145 62,125 Z" />
        <path d="M148,125 Q155,145 150,165 L135,165 Q132,145 138,125 Z" />
      </g>

      {/* Abs */}
      <g id="ant-abs" className={getMuscleClass('Abs')} onClick={() => onMuscleClick('Abs')}>
        <path d="M85,155 L115,155 Q120,200 110,230 L90,230 Q80,200 85,155 Z" />
        {/* Definition lines */}
        <line x1="88" y1="180" x2="112" y2="180" className="stroke-background/40 stroke-[0.5px]" />
        <line x1="88" y1="205" x2="112" y2="205" className="stroke-background/40 stroke-[0.5px]" />
        <line x1="100" y1="155" x2="100" y2="230" className="stroke-background/40 stroke-[0.5px]" />
      </g>

      {/* Obliques */}
      <g id="ant-obliques" className={getMuscleClass('Obliques')} onClick={() => onMuscleClick('Obliques')}>
        <path d="M75,155 Q65,185 75,230 L85,230 Q80,195 85,155 Z" />
        <path d="M125,155 Q135,185 125,230 L115,230 Q120,195 115,155 Z" />
      </g>

      {/* Forearms */}
      <g id="ant-forearms" className={getMuscleClass('Forearms')} onClick={() => onMuscleClick('Forearms')}>
        <path d="M50,170 Q40,200 45,235 L55,235 Q60,200 60,170 Z" />
        <path d="M150,170 Q160,200 155,235 L145,235 Q140,200 140,170 Z" />
      </g>

      {/* Quads */}
      <g id="ant-quads" className={getMuscleClass('Quads')} onClick={() => onMuscleClick('Quads')}>
        <path d="M70,235 Q60,285 75,340 L95,340 Q95,290 90,235 Z" />
        <path d="M130,235 Q140,285 125,340 L105,340 Q105,290 110,235 Z" />
      </g>

      {/* Adductors */}
      <g id="ant-hip-adductors" className={getMuscleClass('Hip Adductors')} onClick={() => onMuscleClick('Hip Adductors')}>
        <path d="M92,235 L108,235 L102,280 L98,280 Z" />
      </g>

    </svg>
  );
}
