"use client"

import * as React from "react"
import { ChevronLeft, ChevronRight } from "lucide-react"
import { DayPicker, DropdownProps } from "react-day-picker" 
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select' 

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
      className={cn("p-3 h-full flex flex-col", className)} 
      classNames={{
        root: cn("flex flex-col flex-grow", classNames?.root), 
        months: cn("flex flex-col sm:flex-row space-y-4 sm:space-x-4 sm:space-y-0 flex-grow", classNames?.months), 
        month: cn("space-y-4 flex flex-col flex-grow", classNames?.month), 
        caption: cn("flex justify-center pt-1 relative items-center h-12 flex-shrink-0 gap-1", classNames?.caption), 
        caption_label: cn("text-sm font-medium hidden", classNames?.caption_label), 
        caption_dropdowns: cn("flex gap-1", classNames?.caption_dropdowns), 
        nav: cn("space-x-1 flex items-center", classNames?.nav),
        nav_button: cn(
          buttonVariants({ variant: "outline" }),
          "h-7 w-7 bg-transparent p-0 opacity-50 hover:opacity-100",
          classNames?.nav_button
        ),
        nav_button_previous: cn("absolute left-1", classNames?.nav_button_previous),
        nav_button_next: cn("absolute right-1", classNames?.nav_button_next),
        table: cn("w-full border-collapse space-y-1 flex-grow", classNames?.table), 
        head_row: cn("flex", classNames?.head_row),
        head_cell: cn(
          "text-muted-foreground rounded-md w-9 font-normal text-[0.8rem]",
          classNames?.head_cell
        ),
        row: cn("flex w-full mt-2", classNames?.row),
        cell: cn(
          "flex-1 p-0 relative [&:has([aria-selected].day-range-end)]:rounded-r-md [&:has([aria-selected].day-outside)]:bg-accent/50 [&:has([aria-selected])]:bg-accent first:[&:has([aria-selected])]:rounded-l-md last:[&:has([aria-selected])]:rounded-r-md focus-within:relative focus-within:z-20",
          "aspect-square flex items-center justify-center", 
          classNames?.cell
        ),
        day: cn(
           buttonVariants({ variant: "ghost" }),
           "h-full w-full aspect-square p-0 font-normal aria-selected:opacity-100 rounded-md", 
           "hover:bg-accent focus:outline-none focus:ring-1 focus:ring-ring", 
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
        dropdown: "rdp-dropdown bg-card", 
        dropdown_icon: "ml-2", 
        dropdown_year: "rdp-dropdown_year ml-2", 
        dropdown_month: "rdp-dropdown_month", 
        ...classNames, 
      }}
      components={{
        IconLeft: ({ ...props }) => <ChevronLeft className="h-4 w-4" {...props} />,
        IconRight: ({ ...props }) => <ChevronRight className="h-4 w-4" {...props} />,
        Dropdown: (dropdownProps: DropdownProps) => {
          const { fromDate, toDate, currentMonth } = dropdownProps; // currentMonth is important
          let selectItems: { label: string; value: string }[] = [];
 
          if (dropdownProps.options && Array.isArray(dropdownProps.options)) {
            selectItems = dropdownProps.options
              .filter(option => typeof option.value === 'number' && option.label !== undefined) 
              .map((option) => ({
                label: option.label!, // Assert label is defined after filter
                value: String(option.value),
              }));
          } else {
             // This case should ideally not happen if react-day-picker is working correctly
             // console.warn("Dropdown options missing or not an array for:", dropdownProps.name, dropdownProps.options);
          }

          // Determine the caption for the SelectTrigger
          // dropdownProps.caption is provided by react-day-picker and is usually correct
          const displayedCaption = dropdownProps.caption || 
            (dropdownProps.name === 'months' ? "Select Month" : "Select Year");

          return (
            <Select
              value={dropdownProps.value !== undefined ? String(dropdownProps.value) : undefined}
              onValueChange={(newValue) => {
                if (dropdownProps.onChange && currentMonth) {
                    const newDate = new Date(currentMonth);
                    if (dropdownProps.name === 'months') {
                        newDate.setMonth(parseInt(newValue, 10));
                    } else if (dropdownProps.name === 'years') {
                        newDate.setFullYear(parseInt(newValue, 10));
                    }
                    dropdownProps.onChange(newDate);
                }
              }}
            >
              <SelectTrigger
                className={cn(
                   buttonVariants({ variant: 'outline' }),
                   'h-7 w-auto px-2 py-0.5 text-xs font-medium data-[state=open]:bg-accent data-[state=open]:text-accent-foreground',
                   dropdownProps.name === 'years' ? 'w-[5.5rem]' : 'w-[8rem]' // Adjusted year width slightly
                )}
              >
                <SelectValue placeholder={dropdownProps.name === 'months' ? "Select Month" : "Select Year"}>
                    {displayedCaption}
                </SelectValue>
              </SelectTrigger>
              <SelectContent 
                className={cn(
                  "max-h-80", // Ensure max height for long lists
                  // Add a min-height to prevent complete collapse if content is unexpectedly empty
                  selectItems.length === 0 ? "min-h-[40px] flex items-center justify-center" : "" 
                )}
              >
                {selectItems.length > 0 ? (
                    selectItems.map((item) => (
                    <SelectItem key={item.value} value={item.value} className="text-xs">
                        {item.label}
                    </SelectItem>
                    ))
                ) : (
                    <div className="p-2 text-xs text-muted-foreground text-center">
                        No options
                    </div>
                )}
              </SelectContent>
            </Select>
          );
        },
      }}
      {...props}
    />
  )
}
Calendar.displayName = "Calendar"

export { Calendar }
