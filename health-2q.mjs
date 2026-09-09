export const MENTAL_2Q_STATUS = Object.freeze({
  ASSESSED: 'assessed',
  NOT_ASSESSED: 'not_assessed',
  INCOMPLETE: 'incomplete',
});

export function parseOptional2QValue(value) {
  if (value === true || value === 'yes') return true;
  if (value === false || value === 'no') return false;
  return null;
}

export function evaluateMental2Q(q1, q2) {
  const first = parseOptional2QValue(q1);
  const second = parseOptional2QValue(q2);
  if (first === null && second === null) {
    return { q1: null, q2: null, status: MENTAL_2Q_STATUS.NOT_ASSESSED, result: null };
  }
  if (first === null || second === null) {
    return { q1: first, q2: second, status: MENTAL_2Q_STATUS.INCOMPLETE, result: null };
  }
  return { q1: first, q2: second, status: MENTAL_2Q_STATUS.ASSESSED, result: first || second };
}

export function mental2QLabel(status, result) {
  if (status === MENTAL_2Q_STATUS.ASSESSED) {
    return result === true ? 'ประเมินแล้ว · พบคำตอบบวก' : 'ประเมินแล้ว · ไม่พบคำตอบบวก';
  }
  if (status === MENTAL_2Q_STATUS.INCOMPLETE) return 'ข้อมูล 2Q ไม่ครบ';
  return 'ไม่ได้ประเมิน';
}
