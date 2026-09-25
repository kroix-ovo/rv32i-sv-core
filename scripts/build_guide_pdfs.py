"""Build the two illustrated repository teaching guides as polished PDFs."""

from __future__ import annotations

from pathlib import Path
from shutil import copyfile

from reportlab.graphics import renderPDF
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import (
    Flowable,
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)
from svglib.svglib import svg2rlg


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output" / "pdf"
DIAGRAMS = ROOT / "docs" / "diagrams"


class SvgFigure(Flowable):
    """Scale an SVG drawing to a predictable space without rasterizing it."""

    def __init__(self, path: Path, max_width: float, max_height: float):
        super().__init__()
        drawing = svg2rlg(str(path))
        if drawing is None:
            raise ValueError(f"Could not read SVG: {path}")
        scale = min(max_width / drawing.width, max_height / drawing.height)
        self.drawing = drawing
        self.scale = scale
        self.width = drawing.width * scale
        self.height = drawing.height * scale

    def draw(self):
        self.canv.saveState()
        self.canv.scale(self.scale, self.scale)
        renderPDF.draw(self.drawing, self.canv, 0, 0)
        self.canv.restoreState()


BASE = getSampleStyleSheet()
NAVY = colors.HexColor("#183153")
TEAL = colors.HexColor("#176b63")
INK = colors.HexColor("#25364a")
MUTED = colors.HexColor("#5f6f7f")
PALE_BLUE = colors.HexColor("#eef5fb")
PALE_TEAL = colors.HexColor("#e8f4f2")
TITLE = ParagraphStyle(
    "GuideTitle",
    parent=BASE["Title"],
    fontName="Times-Bold",
    fontSize=25,
    leading=30,
    alignment=TA_CENTER,
    textColor=NAVY,
    spaceAfter=12,
)
SUBTITLE = ParagraphStyle(
    "GuideSubtitle",
    parent=BASE["Normal"],
    fontName="Helvetica",
    fontSize=10.5,
    leading=15,
    alignment=TA_CENTER,
    textColor=MUTED,
    spaceAfter=18,
)
H1 = ParagraphStyle(
    "H1",
    parent=BASE["Heading1"],
    fontName="Times-Bold",
    fontSize=18,
    leading=22,
    textColor=NAVY,
    spaceBefore=7,
    spaceAfter=8,
    keepWithNext=True,
)
H2 = ParagraphStyle(
    "H2",
    parent=BASE["Heading2"],
    fontName="Helvetica-Bold",
    fontSize=12.5,
    leading=16,
    textColor=TEAL,
    spaceBefore=7,
    spaceAfter=5,
    keepWithNext=True,
)
BODY = ParagraphStyle(
    "Body",
    parent=BASE["BodyText"],
    fontName="Times-Roman",
    fontSize=10.5,
    leading=15,
    alignment=TA_LEFT,
    textColor=INK,
    spaceAfter=7,
)
SMALL = ParagraphStyle(
    "Small",
    parent=BODY,
    fontSize=8.8,
    leading=12,
    textColor=MUTED,
)
CAPTION = ParagraphStyle(
    "Caption",
    parent=SMALL,
    fontName="Helvetica-Oblique",
    alignment=TA_CENTER,
    spaceBefore=4,
    spaceAfter=9,
)
CODE = ParagraphStyle(
    "Code",
    parent=BASE["Code"],
    fontName="Courier",
    fontSize=9.5,
    leading=13,
    leftIndent=12,
    rightIndent=12,
    borderWidth=0.6,
    borderColor=colors.HexColor("#b8c5d1"),
    borderPadding=8,
    backColor=PALE_BLUE,
    spaceBefore=5,
    spaceAfter=9,
)
BULLET = ParagraphStyle(
    "Bullet",
    parent=BODY,
    leftIndent=17,
    firstLineIndent=-9,
    bulletIndent=5,
    spaceAfter=3,
)
CALLOUT = ParagraphStyle(
    "Callout",
    parent=BODY,
    fontName="Helvetica",
    fontSize=10,
    leading=14,
    borderWidth=0.8,
    borderColor=TEAL,
    borderPadding=9,
    backColor=PALE_TEAL,
    spaceBefore=6,
    spaceAfter=10,
)


def code(text: str) -> str:
    return f'<font name="Courier">{text}</font>'


def bullet(text: str) -> Paragraph:
    return Paragraph(f"- {text}", BULLET)


def figure(path: Path, caption: str, max_height: float) -> list[Flowable]:
    return [
        SvgFigure(path, 6.85 * inch, max_height),
        Paragraph(caption, CAPTION),
    ]


def make_table(data, widths, header=True) -> Table:
    table = Table(data, colWidths=widths, repeatRows=1 if header else 0, hAlign="LEFT")
    commands = [
        ("GRID", (0, 0), (-1, -1), 0.45, colors.HexColor("#b8c5d1")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("FONTNAME", (0, 0), (-1, -1), "Helvetica"),
        ("FONTSIZE", (0, 0), (-1, -1), 8.6),
        ("LEADING", (0, 0), (-1, -1), 11),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]
    if header:
        commands.extend([
            ("BACKGROUND", (0, 0), (-1, 0), NAVY),
            ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
            ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ])
    table.setStyle(TableStyle(commands))
    return table


def page_decorator(document_title: str):
    def draw(canvas, doc):
        canvas.saveState()
        width, height = letter
        canvas.setStrokeColor(TEAL)
        canvas.setLineWidth(1.2)
        canvas.line(doc.leftMargin, 0.52 * inch, width - doc.rightMargin, 0.52 * inch)
        canvas.setFont("Helvetica", 8)
        canvas.setFillColor(MUTED)
        canvas.drawString(doc.leftMargin, 0.35 * inch, document_title)
        canvas.drawRightString(width - doc.rightMargin, 0.35 * inch, f"Page {doc.page}")
        canvas.restoreState()
    return draw


def document(path: Path, title: str) -> SimpleDocTemplate:
    return SimpleDocTemplate(
        str(path),
        pagesize=letter,
        rightMargin=0.72 * inch,
        leftMargin=0.72 * inch,
        topMargin=0.65 * inch,
        bottomMargin=0.7 * inch,
        title=title,
        author="RV32I SystemVerilog CPU Core contributors",
        subject="Open hardware education",
    )


def build_architecture() -> Path:
    """Build the current pipeline guide from the checked-in RTL contract."""
    path = OUTPUT / "architecture.pdf"
    story: list[Flowable] = [
        Spacer(1, 0.18 * inch),
        Paragraph("RV32I five-stage pipeline", TITLE),
        Paragraph("IF, ID, EX, MEM, WB: instruction flow, stalls, traps, and FPGA evidence", SUBTITLE),
        *figure(DIAGRAMS / "core_datapath.svg", "Figure 1. The valid bits mark occupied stage registers; adjacent instructions may overlap.", 3.8 * inch),
        Paragraph("Design scope", H1),
        Paragraph("The core implements unprivileged RV32I with separate ready/valid instruction and data ports. It has 32 integer registers, little-endian byte lanes, alignment checks, and a sticky external trap record. It has no forwarding, caches, privileged CSRs, interrupts, MMU, compressed instructions, or multiply/divide extension.", BODY),
        Paragraph("Pipeline registers hold an instruction's PC, data, and control decisions. A valid bit of zero marks a bubble: the nearby data bits are ignored. Unlike the earlier multicycle design, several different instructions can occupy the pipeline at once.", CALLOUT),
        PageBreak(),
        Paragraph("What each stage does", H1),
        make_table([
            ["Stage", "Work", "Result"],
            ["IF", "Hold imem_valid_o and fetch_pc_q until imem_ready_i.", "Instruction and PC enter IF/ID."],
            ["ID", "Decode, form the immediate, and read source registers.", "Operands and controls enter ID/EX when dependencies clear."],
            ["EX", "Run ALU and branch comparison; form data address.", "Result or memory request enters EX/MEM."],
            ["MEM", "Hold a load/store request until dmem_ready_i; align load data.", "Result enters MEM/WB."],
            ["WB", "Write rd when legal, then pulse retirement.", "Architectural register state changes."],
        ], [0.6 * inch, 3.15 * inch, 2.65 * inch]),
        Spacer(1, 12),
        *figure(DIAGRAMS / "control_fsm.svg", "Figure 2. Pipeline flow, interlocks, and fault handling. This is not a state machine.", 2.9 * inch),
        Paragraph("Reading the SystemVerilog", H2),
        Paragraph("The suffix _q means a clocked value. always_comb describes logic that responds within a cycle. always_ff updates registers on a clock edge. A nonblocking assignment (<=) reads the old values for that edge, so neighboring instructions can advance together.", BODY),
        PageBreak(),
        Paragraph("Hazards and control flow", H1),
        Paragraph("There is no bypass network. If an instruction in ID reads a register that an older instruction will write, ID waits. A bubble moves forward until the older instruction writes in WB. For example, ADDI x1,x0,7 followed by ADD x2,x1,x1 waits for x1; the ADD then reads 7 and produces 14.", BODY),
        Paragraph("A waiting data request holds EX/MEM and younger stages. WB can still retire an older instruction once. Fetch pauses for an unresolved branch or jump, a memory operation, FENCE, or a fault. A branch or jump resolves in EX and supplies the next fetch PC. This simple policy limits throughput below one instruction per cycle.", BODY),
        Paragraph("Instruction and data handshakes", H2),
        Paragraph("A request is valid while its address and controls stay stable. The matching ready input completes it. The core permits one outstanding request and pauses fetch during data-memory work. No request queue, write buffer, or cache changes the ordering.", BODY),
        Paragraph("Faults and retirement", H2),
        Paragraph("A memory-stage fault has priority over an execute-stage fault, which has priority over a fetch fault. The faulting instruction does not retire or write rd. Younger work is discarded; older work retires before trap_valid_o becomes sticky. trap_cause_o, trap_pc_o, and trap_tval_o report the fault until reset.", BODY),
        Paragraph("debug_state_o is a status summary: 0 means flowing, 1 interlock or serialization, 2 memory wait, and 3 trapped. It is not a pipeline stage number.", CALLOUT),
        PageBreak(),
        Paragraph("Data operations and integration", H1),
        Paragraph("The decoder checks opcode, funct3, and funct7. The immediate generator reconstructs I, S, B, U, and J layouts. The ALU handles arithmetic, logic, shifts, and signed or unsigned comparisons. Instruction addresses must be four-byte aligned; misaligned halfword or word data accesses trap.", BODY),
        make_table([
            ["Access", "Legal low address bits", "Write strobe"],
            ["SB", "00, 01, 10, 11", "0001, 0010, 0100, 1000"],
            ["SH", "00 or 10", "0011 or 1100"],
            ["SW", "00", "1111"],
        ], [0.85 * inch, 2.3 * inch, 3.25 * inch]),
        Spacer(1, 10),
        Paragraph("Loads select a byte or halfword from the returned aligned word. LB and LH sign extend; LBU and LHU fill upper bits with zeros. JAL and JALR write PC + 4 when they complete successfully. JALR clears target bit 0, and the four-byte alignment check still applies.", BODY),
        Paragraph("The SoC wrapper uses two clocked ports of a shared memory array so Vivado can infer block RAM. The FPGA top targets the Arty A7-100T. The bitstream was generated, but board execution has not been observed.", BODY),
        *figure(DIAGRAMS / "instruction_formats.svg", "Figure 3. RV32I instruction fields. Immediate bits are reassembled by the immediate generator.", 2.35 * inch),
        PageBreak(),
        Paragraph("Verification and measured implementation", H1),
        Paragraph("The cocotb environment separates a memory driver, request monitors, an independent Python ISA scoreboard, and coverage checks. This uses UVM-style roles without a SystemVerilog UVM library. Directed SystemVerilog benches check ALU operations, the instruction program, and traps.", BODY),
        *figure(DIAGRAMS / "verification_stack.svg", "Figure 4. Checks observe the core through memory transactions and retirement outputs.", 3.3 * inch),
        make_table([
            ["Check", "Observed result"],
            ["Icarus directed benches", "10 ALU checks; program signature in 521 cycles; 9 traps"],
            ["cocotb 2.0.1", "3 tests passed, including pipeline hazards and wait states"],
            ["Vivado 2023.2 XSim", "ALU, directed, and trap benches passed"],
            ["Arty A7-100T post-route", "WNS +0.681 ns at 10 ns; 1,631 LUTs; 1,560 registers; 4 RAMB36"],
        ], [2.1 * inch, 4.3 * inch]),
        Spacer(1, 8),
        Paragraph("The implementation run had 0 DRC errors and 26 warnings. These are report results, not physical-board measurements. See docs/pipeline_vivado_report.md for warnings and build details.", CALLOUT),
    ]
    doc = document(path, "RV32I five-stage pipeline architecture")
    decorate = page_decorator("RV32I five-stage pipeline")
    doc.build(story, onFirstPage=decorate, onLaterPages=decorate)
    return path


def build_learning_guide() -> Path:
    """Follow a load through overlapping stages and a held memory request."""
    path = OUTPUT / "learning_guide.pdf"
    story: list[Flowable] = [
        Spacer(1, 0.25 * inch),
        Paragraph("Following one load instruction", TITLE),
        Paragraph("A waveform lesson for the IF/ID/EX/MEM/WB RV32I pipeline", SUBTITLE),
        Paragraph("Example instruction", H1),
        Paragraph("lw x5, 12(x3)", CODE),
        Spacer(1, 18),
        Paragraph("The instruction adds 12 to x3, reads a 32-bit word at that byte address, and writes the word to x5. Another independent instruction can be in a different stage while this load progresses.", CALLOUT),
        *figure(DIAGRAMS / "core_datapath.svg", "Figure 1. The load crosses IF, ID, EX, MEM, and WB. A valid bit identifies its occupied stage.", 3.55 * inch),
        Paragraph("Signals to inspect", H1),
        make_table([
            ["Signal", "What it tells you"],
            ["if_valid_q / id_valid_q", "An accepted instruction and a decoded instruction are present."],
            ["ex_valid_q / wb_valid_q", "A memory request or a result waiting to retire is present."],
            ["dmem_valid_o / dmem_ready_i", "The load is requested and then completed."],
            ["retire_valid_o", "The load has reached architectural retirement."],
        ], [2.25 * inch, 4.15 * inch]),
        PageBreak(),
        Paragraph("1. IF and ID", H1),
        Paragraph("At IF, imem_addr_o equals fetch_pc_q. imem_valid_o stays high until imem_ready_i accepts the instruction. The fetched word and its PC enter the IF/ID register, marked by if_valid_q.", BODY),
        Paragraph("ID recognizes opcode 0000011 and funct3 010 as LW. It sign extends the I-type immediate 12 and reads x3. If an older instruction will write x3, dependency holds the load in ID until that write reaches WB. A bubble moves ahead while the load waits.", BODY),
        Paragraph("2. EX", H1),
        Paragraph("The ALU adds the x3 value to 12. For LW, address bits [1:0] must be 00. A misaligned address creates a load-address-misaligned fault before any data request. Otherwise the effective address and load controls enter EX/MEM.", BODY),
        Paragraph("3. MEM", H1),
        Paragraph("dmem_valid_o stays high with a stable dmem_addr_o while dmem_ready_i is low. EX/MEM and younger stages wait. When ready rises, the returned 32-bit word is selected; dmem_error_i instead records a load access fault.", BODY),
        *figure(DIAGRAMS / "load_timeline.svg", "Figure 2. A held load request; stage occupancy can overlap with older or younger work.", 2.65 * inch),
        PageBreak(),
        Paragraph("4. WB and retirement", H1),
        Paragraph("The completed load enters MEM/WB. On its WB edge, the register file writes x5 and retire_valid_o pulses with the load's PC and instruction word. A faulting load does neither. x0 remains zero even if selected as the destination.", BODY),
        Paragraph("Try a dependent instruction", H1),
        Paragraph("Place ADD x6,x5,x5 after the load. Because this baseline has no forwarding, the ADD stays in ID until the load writes x5. Then it reads the new word twice. In the waveform, look for the held IF/ID instruction, a bubble ahead of it, and a later retirement pulse.", BODY),
        Paragraph("Try a byte load", H1),
        Paragraph("Change LW to LB and the offset to 13. A byte address may have nonzero low bits. Memory still returns the aligned 32-bit word; the core selects the addressed byte and sign extends bit 7. LBU would zero extend that same byte.", BODY),
        Paragraph("Reproduce the waveform", H1),
        Paragraph("Run make test-cocotb-waves PYTHON=.venv/bin/python. Open sim/build/cocotb/dump.fst with waves/rv32i_core.gtkw. The scoreboard and assertions determine pass/fail; the waveform lets you see why the pipeline stalled or advanced.", BODY),
    ]
    doc = document(path, "Following one load in the RV32I pipeline")
    decorate = page_decorator("RV32I pipeline load lesson")
    doc.build(story, onFirstPage=decorate, onLaterPages=decorate)
    return path


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    generated = [build_architecture(), build_learning_guide()]
    for item in generated:
        # Keep the convenience copies in docs/ identical to the canonical PDFs.
        copyfile(item, ROOT / "docs" / item.name)
        print(item)
