import {
  PageHeader,
  PlaceholderPanel,
} from "@/components/shell/page-header"

export default function PropertiesPage() {
  return (
    <>
      <PageHeader
        title="Properties"
        description="Manage the sites and buildings your team inspects."
      />
      <PlaceholderPanel feature="Property list" />
    </>
  )
}
