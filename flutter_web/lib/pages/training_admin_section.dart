enum TrainingAdminSection {
  overview,
  needs,
  program,
  list,
  effectiveness,
  archive,
}

String trainingAdminSectionPath(TrainingAdminSection section) {
  switch (section) {
    case TrainingAdminSection.overview:
      return '/admin/training';
    case TrainingAdminSection.needs:
      return '/admin/training/needs';
    case TrainingAdminSection.program:
      return '/admin/training/program';
    case TrainingAdminSection.list:
      return '/admin/training/list';
    case TrainingAdminSection.effectiveness:
      return '/admin/training/effectiveness';
    case TrainingAdminSection.archive:
      return '/admin/training/archive';
  }
}

TrainingAdminSection trainingAdminSectionFromPathSegment(String? segment) {
  switch (segment) {
    case 'needs':
      return TrainingAdminSection.needs;
    case 'program':
      return TrainingAdminSection.program;
    case 'list':
      return TrainingAdminSection.list;
    case 'effectiveness':
      return TrainingAdminSection.effectiveness;
    case 'archive':
      return TrainingAdminSection.archive;
    default:
      return TrainingAdminSection.overview;
  }
}
