'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Dumbbell, CalendarDays, Settings, PanelLeft } from 'lucide-react';
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

const navItems = getDays().map(day => ({
  href: `/workout/${day.id}`,
  icon: CalendarDays,
  label: day.dayName,
  subLabel: day.title,
}));

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
            <SidebarMenu className="p-2 lg:p-4">
              {navItems.map((item) => (
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
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 md:p-8">
          {children}
        </main>
      </SidebarInset>
    </>
  );
}
