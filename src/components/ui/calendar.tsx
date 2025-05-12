
"use client"

import * as React from "react"
import { ChevronLeft, ChevronRight } from "lucide-react"
import { DayPicker, DropdownProps } from "react-day-picker" // Import DropdownProps
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select' // Import Select components
import { ScrollArea } from "./scroll-area"; // Import ScrollArea

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
        caption: cn("flex justify-center pt-1 relative items-center h-12 flex-shrink-0 gap-1", classNames?.caption), // Adjusted height for dropdowns
        caption_label: cn("text-sm font-medium hidden", classNames?.caption_label), // Hide label when dropdowns are visible
        caption_dropdowns: cn("flex gap-1", classNames?.caption_dropdowns), // Style dropdown container
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
        dropdown: "rdp-dropdown bg-card", // Style dropdown container
        dropdown_icon: "ml-2", // Style dropdown icon
        dropdown_year: "rdp-dropdown_year ml-2", // Style year dropdown container
        dropdown_month: "rdp-dropdown_month", // Style month dropdown container
        ...classNames, // Spread remaining custom classNames
      }}
      components={{
        IconLeft: ({ ...props }) => <ChevronLeft className="h-4 w-4" {...props} />,
        IconRight: ({ ...props }) => <ChevronRight className="h-4 w-4" {...props} />,
        // Use shadcn Select for dropdowns
        Dropdown: (dropdownProps: DropdownProps) => {
          const { fromDate, toDate } = dropdownProps;
          const fromMonth = fromDate ? fromDate.getMonth() : undefined;
          const fromYear = fromDate ? fromDate.getFullYear() : undefined;
          const toMonth = toDate ? toDate.getMonth() : undefined;
          const toYear = toDate ? toDate.getFullYear() : undefined;
          let selectItems: { label: string; value: string }[] = [];

          if (dropdownProps.name === 'months') {
            selectItems = dropdownProps.options.map((option) => ({
              label: option.label,
              value: String(option.value?.getMonth()),
            }));
          } else if (dropdownProps.name === 'years') {
            selectItems = dropdownProps.options.map((option) => ({
              label: option.label,
              value: String(option.value?.getFullYear()),
            }));
          }

           const caption =
            dropdownProps.caption ??
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            (dropdownProps.name === 'months'
              ? // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
                dropdownProps.locale!.months![
                  dropdownProps.value! as number
                ]
              : dropdownProps.value);

          return (
            <Select
              value={String(dropdownProps.value)}
              onValueChange={(newValue) => {
                if (dropdownProps.name === 'months') {
                   dropdownProps.onChange?.(
                    new Date(
                      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
                      dropdownProps.currentMonth!.getFullYear(),
                      parseInt(newValue, 10)
                    )
                  );
                } else if (dropdownProps.name === 'years') {
                  dropdownProps.onChange?.(
                    new Date(
                      parseInt(newValue, 10),
                      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
                      dropdownProps.currentMonth!.getMonth()
                    )
                  );
                }
              }}
            >
              <SelectTrigger
                className={cn(
                   buttonVariants({ variant: 'outline' }),
                   'h-7 w-auto px-2 py-0.5 text-xs font-medium data-[state=open]:bg-accent data-[state=open]:text-accent-foreground',
                   dropdownProps.name === 'years' ? 'w-[4.5rem]' : 'w-[8rem]' // Adjust width as needed
                )}
              >
                <SelectValue>{caption}</SelectValue>
              </SelectTrigger>
              <SelectContent>
                 <ScrollArea className={cn(
                    "h-80", // Fixed height for scrollable area
                    dropdownProps.name === 'years' ? 'w-[4.5rem]' : 'w-[8rem]'
                  )}>
                    {selectItems.map((item) => (
                    <SelectItem key={item.value} value={item.value} className="text-xs">
                        {item.label}
                    </SelectItem>
                    ))}
                 </ScrollArea>
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

