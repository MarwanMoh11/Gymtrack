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
      {/* Head */}
      <rect x="80" y="20" width="40" height="40" className="fill-muted-foreground/20" />
      
      {/* Neck */}
      <rect x="90" y="60" width="20" height="10" className="fill-muted-foreground/20" />

      {/* Shoulders */}
      <g id="ant-shoulders" className={getMuscleClass('Shoulders')} onClick={() => onMuscleClick('Shoulders')}>
        <rect x="50" y="70" width="100" height="20" />
      </g>
      
      {/* Chest */}
      <g id="ant-chest" className={getMuscleClass('Chest')} onClick={() => onMuscleClick('Chest')}>
        <rect x="70" y="90" width="60" height="40" />
      </g>

      {/* Biceps */}
      <g id="ant-biceps" className={getMuscleClass('Biceps')} onClick={() => onMuscleClick('Biceps')}>
        <rect x="50" y="90" width="20" height="50" />
        <rect x="130" y="90" width="20" height="50" />
      </g>

      {/* Abs */}
      <g id="ant-abs" className={getMuscleClass('Abs')} onClick={() => onMuscleClick('Abs')}>
        <rect x="70" y="130" width="60" height="60" />
      </g>

      {/* Obliques */}
      <g id="ant-obliques" className={getMuscleClass('Obliques')} onClick={() => onMuscleClick('Obliques')}>
        <rect x="60" y="130" width="10" height="60" />
        <rect x="130" y="130" width="10" height="60" />
      </g>

      {/* Forearms */}
      <g id="ant-forearms" className={getMuscleClass('Forearms')} onClick={() => onMuscleClick('Forearms')}>
        <rect x="50" y="140" width="10" height="60" />
        <rect x="140" y="140" width="10" height="60" />
      </g>
      
      {/* Hip Adductors */}
      <g id="ant-hip-adductors" className={getMuscleClass('Hip Adductors')} onClick={() => onMuscleClick('Hip Adductors')}>
        <rect x="80" y="190" width="40" height="40" />
      </g>

      {/* Quads */}
      <g id="ant-quads" className={getMuscleClass('Quads')} onClick={() => onMuscleClick('Quads')}>
        <rect x="60" y="190" width="20" height="100" />
        <rect x="120" y="190" width="20" height="100" />
      </g>

      {/* Lower Legs */}
       <rect x="60" y="290" width="20" height="80" className="fill-muted-foreground/20" />
       <rect x="120" y="290" width="20" height="80" className="fill-muted-foreground/20" />

    </svg>
  );
}
