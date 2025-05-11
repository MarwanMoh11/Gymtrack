import { Dumbbell } from 'lucide-react';
import type { SVGProps } from 'react';

export function Logo(props: SVGProps<SVGSVGElement>) {
  return (
    <Dumbbell className="h-8 w-8 text-sidebar-primary" {...props} />
  );
}
