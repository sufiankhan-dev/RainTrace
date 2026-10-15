import {
  PageHeader,
  PlaceholderPanel,
} from "@/components/shell/page-header"

export default function InspectionsPage() {
  return (
    <>
      <PageHeader
        title="Inspections"
        description="Review inspection history and confirmed findings."
      />
      <PlaceholderPanel feature="Inspection history" />
    </>
  )
}
