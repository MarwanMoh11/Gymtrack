
'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { CalendarCheck, Dumbbell, CalendarDays, Settings, PanelLeft, TrendingUp } from 'lucide-react';
import {
  Sidebar,
  SidebarHeader,
  SidebarContent,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuButton,
  SidebarFooter,
  SidebarInset,
  SidebarTrigger,
  useSidebar,
} from '@/components/ui/sidebar';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Logo } from '@/components/icons/logo';
import { getDays } from '@/data/workout-data';
import { Separator } from '@/components/ui/separator';

const workoutNavItems = getDays().map(day => ({
  href: `/workout/${day.id}`,
  icon: CalendarDays,
  label: day.dayName,
  subLabel: day.title,
}));

const mainNavItems = [
  {
    href: '/dashboard/progressive-overload',
    icon: TrendingUp,
    label: 'Progress Dashboard',
    subLabel: 'Track your gains',
  }
];

const todayNavItem = {
  href: '/dashboard/today',
  icon: CalendarCheck,
  label: "Today's Session",
  subLabel: 'Log your current workout',
};

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { open, isMobile, setOpenMobile } = useSidebar();

  const handleLinkClick = () => {
    if (isMobile) {
      setOpenMobile(false);
    }
  };

  return (
    <>
      <Sidebar variant="sidebar" collapsible="icon">
        <SidebarHeader className="p-4">
            <div className="flex items-center gap-3">
              <Logo />
              <h1 className="text-2xl font-semibold text-sidebar-foreground group-data-[collapsible=icon]:hidden">
                GymTrack
              </h1>
            </div>
        </SidebarHeader>
        <Separator className="bg-sidebar-border group-data-[collapsible=icon]:hidden" />
        <SidebarContent asChild>
          <ScrollArea className="h-full">
            {/* Today's Session Link - Placed at the top */}
            <SidebarMenu className="p-2 lg:p-4">
              <SidebarMenuItem key={todayNavItem.href}>
                <SidebarMenuButton
                  asChild
                  isActive={pathname === todayNavItem.href}
                  variant="default"
                  size="lg"
                  className="justify-start"
                  tooltip={todayNavItem.label}
                >
                  <Link href={todayNavItem.href} onClick={handleLinkClick}>
                    <todayNavItem.icon />
                    <div className="flex flex-col items-start">
                      <span>{todayNavItem.label}</span>
                      {todayNavItem.subLabel && <span className="text-xs text-sidebar-foreground/70 group-data-[collapsible=icon]:hidden">{todayNavItem.subLabel}</span>}
                    </div>
                  </Link>
                </SidebarMenuButton>
              </SidebarMenuItem>
            </SidebarMenu>

            {/* Separator before other navigation sections */}
            {(mainNavItems.length > 0 || workoutNavItems.length > 0) && (
                <Separator className="my-2 bg-sidebar-border group-data-[collapsible=icon]:hidden" />
            )}

            {/* Main Navigation Items (e.g., Progress Dashboard) */}
            {mainNavItems.length > 0 && (
              <SidebarMenu className="p-2 lg:p-4">
                {mainNavItems.map((item) => (
                  <SidebarMenuItem key={item.href}>
                    <SidebarMenuButton
                      asChild
                      isActive={pathname === item.href || pathname.startsWith(item.href + '/')}
                      variant="default"
                      size="lg"
                      className="justify-start"
                      tooltip={item.label}
                    >
                      <Link href={item.href} onClick={handleLinkClick}>
                        <item.icon />
                        <div className="flex flex-col items-start">
                          <span>{item.label}</span>
                          {item.subLabel && <span className="text-xs text-sidebar-foreground/70 group-data-[collapsible=icon]:hidden">{item.subLabel}</span>}
                        </div>
                      </Link>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            )}
            
            {/* Separator before Daily Workouts if both mainNav and workoutNav exist */}
            {mainNavItems.length > 0 && workoutNavItems.length > 0 && (
                 <Separator className="my-2 bg-sidebar-border group-data-[collapsible=icon]:hidden" />
            )}

            {/* Daily Workouts Section */}
            {workoutNavItems.length > 0 && (
              <>
                <SidebarHeader className="px-2 lg:px-4 pt-2 pb-1 group-data-[collapsible=icon]:hidden">
                  <span className="text-xs font-medium uppercase text-sidebar-foreground/70">Daily Workouts</span>
                </SidebarHeader>
                <SidebarMenu className="p-2 lg:p-4">
                  {workoutNavItems.map((item) => (
                    <SidebarMenuItem key={item.href}>
                      <SidebarMenuButton
                        asChild
                        isActive={pathname === item.href}
                        variant="default"
                        size="lg"
                        className="justify-start"
                        tooltip={item.label}
                      >
                        <Link href={item.href} onClick={handleLinkClick}>
                          <item.icon />
                          <div className="flex flex-col items-start">
                            <span>{item.label}</span>
                            <span className="text-xs text-sidebar-foreground/70 group-data-[collapsible=icon]:hidden">{item.subLabel}</span>
                          </div>
                        </Link>
                      </SidebarMenuButton>
                    </SidebarMenuItem>
                  ))}
                </SidebarMenu>
              </>
            )}
          </ScrollArea>
        </SidebarContent>
        {/* <SidebarFooter className="p-4">
          <SidebarMenuButton
            variant="default"
            size="default"
            className="justify-start"
            tooltip="Settings"
          >
            <Settings />
            <span>Settings</span>
          </SidebarMenuButton>
        </SidebarFooter> */}
      </Sidebar>
      <SidebarInset className="flex flex-col">
        <header className="sticky top-0 z-10 flex h-14 items-center gap-4 border-b bg-background/80 px-4 backdrop-blur-sm sm:h-16 sm:px-6 md:hidden">
          <SidebarTrigger asChild>
            <Button size="icon" variant="outline">
              <PanelLeft />
              <span className="sr-only">Toggle Menu</span>
            </Button>
          </SidebarTrigger>
          <div className="flex items-center gap-2">
            <Dumbbell className="h-6 w-6 text-primary" />
            <h1 className="text-lg font-semibold">GymTrack</h1>
          </div>
        </header>
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 md:p-8 bg-background text-foreground">
          {children}
        </main>
      </SidebarInset>
    </>
  );
}
