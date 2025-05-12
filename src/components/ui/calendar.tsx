
"use client"

import * as React from "react"
import { ChevronLeft, ChevronRight } from "lucide-react"
import { DayPicker } from "react-day-picker"

import { cn } from "@/lib/utils"
import { buttonVariants } from "@/components/ui/button"

export type CalendarProps = React.ComponentProps<typeof DayPicker>

function Calendar({
  className,
  classNames,
  showOutsideDays = true,
  ...props
}: CalendarProps) {
  return (
    <DayPicker
      showOutsideDays={showOutsideDays}
      className={cn("p-3 h-full flex flex-col", className)} // Added h-full flex flex-col
      classNames={{
        root: cn("flex flex-col flex-grow", classNames?.root), // Ensure root takes space
        months: cn("flex flex-col sm:flex-row space-y-4 sm:space-x-4 sm:space-y-0 flex-grow", classNames?.months), // flex-grow added
        month: cn("space-y-4 flex flex-col flex-grow", classNames?.month), // flex-grow added
        caption: cn("flex justify-center pt-1 relative items-center h-10 flex-shrink-0", classNames?.caption), // fixed height
        caption_label: cn("text-sm font-medium", classNames?.caption_label),
        nav: cn("space-x-1 flex items-center", classNames?.nav),
        nav_button: cn(
          buttonVariants({ variant: "outline" }),
          "h-7 w-7 bg-transparent p-0 opacity-50 hover:opacity-100",
          classNames?.nav_button
        ),
        nav_button_previous: cn("absolute left-1", classNames?.nav_button_previous),
        nav_button_next: cn("absolute right-1", classNames?.nav_button_next),
        table: cn("w-full border-collapse space-y-1 flex-grow", classNames?.table), // flex-grow added
        head_row: cn("flex", classNames?.head_row),
        head_cell: cn(
          "text-muted-foreground rounded-md w-9 font-normal text-[0.8rem]",
          classNames?.head_cell
        ),
        row: cn("flex w-full mt-2", classNames?.row),
        // Adjusted cell for aspect ratio and flex centering
        cell: cn(
          "flex-1 p-0 relative [&:has([aria-selected].day-range-end)]:rounded-r-md [&:has([aria-selected].day-outside)]:bg-accent/50 [&:has([aria-selected])]:bg-accent first:[&:has([aria-selected])]:rounded-l-md last:[&:has([aria-selected])]:rounded-r-md focus-within:relative focus-within:z-20",
          "aspect-square flex items-center justify-center", // Ensure square cells and center content
          classNames?.cell
        ),
        // Adjusted day to fill cell and handle hover/focus
        day: cn(
           buttonVariants({ variant: "ghost" }),
           "h-full w-full aspect-square p-0 font-normal aria-selected:opacity-100 rounded-md", // Fill cell, make square, ensure rounded
           "hover:bg-accent focus:outline-none focus:ring-1 focus:ring-ring", // Hover/focus styling
          classNames?.day
        ),
        day_range_end: cn("day-range-end", classNames?.day_range_end),
        day_selected: cn(
          "bg-primary text-primary-foreground hover:bg-primary hover:text-primary-foreground focus:bg-primary focus:text-primary-foreground",
          classNames?.day_selected
        ),
        day_today: cn("bg-accent text-accent-foreground", classNames?.day_today),
        day_outside: cn(
          "day-outside text-muted-foreground opacity-50 aria-selected:bg-accent/50 aria-selected:text-muted-foreground",
          classNames?.day_outside
        ),
        day_disabled: cn("text-muted-foreground opacity-50", classNames?.day_disabled),
        day_range_middle: cn(
          "aria-selected:bg-accent aria-selected:text-accent-foreground",
          classNames?.day_range_middle
        ),
        day_hidden: cn("invisible", classNames?.day_hidden),
        ...classNames, // Spread remaining custom classNames
      }}
      components={{
        IconLeft: ({ ...props }) => <ChevronLeft className="h-4 w-4" {...props} />,
        IconRight: ({ ...props }) => <ChevronRight className="h-4 w-4" {...props} />,
      }}
      {...props}
    />
  )
}
Calendar.displayName = "Calendar"

export { Calendar }

