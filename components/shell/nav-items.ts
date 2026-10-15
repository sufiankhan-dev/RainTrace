import {
  Building2,
  ClipboardList,
  FileText,
  LayoutDashboard,
  type LucideIcon,
} from "lucide-react"

export type NavItem = {
  href: string
  label: string
  description: string
  icon: LucideIcon
}

export const navItems: NavItem[] = [
  {
    href: "/",
    label: "Overview",
    description: "Workspace summary and recent activity",
    icon: LayoutDashboard,
  },
  {
    href: "/properties",
    label: "Properties",
    description: "Sites under management",
    icon: Building2,
  },
  {
    href: "/inspections",
    label: "Inspections",
    description: "Inspection history and findings",
    icon: ClipboardList,
  },
  {
    href: "/reports",
    label: "Reports",
    description: "Shareable inspection reports",
    icon: FileText,
  },
]

export function isActivePath(pathname: string, href: string) {
  if (href === "/") return pathname === "/"
  return pathname === href || pathname.startsWith(`${href}/`)
}
