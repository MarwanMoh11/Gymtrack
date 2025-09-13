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
      viewBox="0 0 350 800"
      aria-label="Anterior view of muscle groups"
      {...props}
    >
      <g id="anterior-view" transform="translate(20, 0)">
        <path
          id="ant-shoulders"
          className={getMuscleClass('Shoulders')}
          onClick={() => onMuscleClick('Shoulders')}
          d="M198.2,143.4l-31.5,13.3l-34.9-13.3L130.6,128l37.7-10.6l31.5,13.3V143.4z"
        />
        <path
          id="ant-chest"
          className={getMuscleClass('Chest')}
          onClick={() => onMuscleClick('Chest')}
          d="M198.2,156.7v38.8h-11.7v12.2H150v-12.2h-16.1v-38.8L130.6,145l37.7-10.6l31.5,13.3V156.7z"
        />
        <path
          id="ant-biceps"
          className={getMuscleClass('Biceps')}
          onClick={() => onMuscleClick('Biceps')}
          d="M231.6,195.5v32.2h-14.5v12.2h-8.9V212h-9.9v-16.5H231.6z M102.8,195.5v32.2h14.5v12.2h8.9V212h9.9v-16.5H102.8z"
        />
        <path
          id="ant-forearms"
          className={getMuscleClass('Forearms')}
          onClick={() => onMuscleClick('Forearms')}
          d="M231.6,239.9v35.4h-10.9v10.1h-10.9v-11.2h-11.9v-34.3H231.6z M102.8,239.9v35.4h10.9v10.1h10.9v-11.2h11.9v-34.3H102.8z"
        />
        <path
          id="ant-abs"
          className={getMuscleClass('Abs')}
          onClick={() => onMuscleClick('Abs')}
          d="M186.5,207.7v81.1h-74.8V207.7H186.5z"
        />
        <path
          id="ant-obliques"
          className={getMuscleClass('Obliques')}
          onClick={() => onMuscleClick('Obliques')}
          d="M206.5,207.7v63.3h-19.9V207.7H206.5z M96.1,207.7v63.3h19.9V207.7H96.1z"
        />
        <path
          id="ant-quads"
          className={getMuscleClass('Quads')}
          onClick={() => onMuscleClick('Quads')}
          d="M186.5,309.5v140h-24.8v-140h-24.8v140h-24.8v-140H186.5z"
        />
        <path
          id="ant-hip-adductors"
          className={getMuscleClass('Hip Adductors')}
          onClick={() => onMuscleClick('Hip Adductors')}
          d="M161.7,309.5v100h-24.8v-100H161.7z"
        />
      </g>
    </svg>
  );
}
