"""Build the two illustrated repository teaching guides as polished PDFs."""

from __future__ import annotations

from pathlib import Path

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
    path = OUTPUT / "architecture.pdf"
    story: list[Flowable] = [
        Spacer(1, 0.22 * inch),
        Paragraph("RV32I core architecture", TITLE),
        Paragraph(
            "A readable guide to the multicycle controller, datapath, memory ports, and trap boundary",
            SUBTITLE,
        ),
        *figure(DIAGRAMS / "core_datapath.svg", "Figure 1. Main datapath and control paths.", 3.95 * inch),
        Paragraph("Design scope", H1),
        Paragraph(
            "This core implements the complete unprivileged RV32I base instruction set. It has separate instruction and data memory ports, a 32-register file, alignment checks, and a sticky external trap record. It does not implement compressed instructions, multiplication, privileged CSRs, interrupts, caches, or an MMU.",
            BODY,
        ),
        Paragraph(
            "The design favors readable behavior over peak throughput. Each instruction completes before the next one begins, so there are no pipeline hazards to hide the basic movement of data.",
            CALLOUT,
        ),
        Paragraph(
            "The diagrams are original to this repository and trace the checked-in RTL. The instruction-format notation follows the official RISC-V RV32I specification; Ibex is cited as a reference for verification-minded open-core documentation, not as copied RTL.",
            SMALL,
        ),
        PageBreak(),
        Paragraph("Why the core is multicycle", H1),
        Paragraph(
            "A single-cycle CPU asks one clock period to cover instruction memory, decode, register reads, the ALU, data memory, and writeback. That drawing is useful in an introductory lesson, but it assumes combinational memories and creates a long timing path.",
            BODY,
        ),
        Paragraph(
            "This core separates the work into states. The state machine is small enough to understand without pipeline hazards, and the memory ports can wait for a real response.",
            BODY,
        ),
        *figure(DIAGRAMS / "control_fsm.svg", "Figure 2. Four-state control machine.", 3.55 * inch),
        Paragraph("Ordinary instruction sequence", H2),
        bullet(f"{code('FETCH')} holds {code('imem_valid_o')} and the PC until instruction memory raises {code('imem_ready_i')}."),
        bullet(f"{code('EXECUTE')} decodes the saved instruction, reads registers, computes the result, and chooses the next PC."),
        bullet(f"{code('MEMORY')} is used only by a load or store and waits for {code('dmem_ready_i')}."),
        bullet(f"{code('TRAP')} holds the fault record until reset."),
        PageBreak(),
        Paragraph("Datapath blocks", H1),
        Paragraph("Program counter and instruction register", H2),
        Paragraph(
            f"The program counter is a byte address. Because the compressed extension is absent, every instruction is four bytes and legal instruction addresses satisfy {code('pc[1:0] == 2\'b00')}. The fetched instruction stays in a register while decode and execution finish.",
            BODY,
        ),
        Paragraph("Decoder and immediate generator", H2),
        Paragraph(
            f"The decoder checks the opcode, {code('funct3')}, and {code('funct7')} fields. Reserved encodings become illegal-instruction traps. The immediate generator reconstructs I, S, B, U, and J layouts. Branch and jump outputs already contain their low zero bit, so they are ready to add to the PC.",
            BODY,
        ),
        Paragraph("Register file", H2),
        Paragraph(
            "Two combinational read ports supply the usual two source operands. One clocked write port records the result. Register x0 is protected twice: reads return zero explicitly, and sequential logic forces its stored value to zero.",
            BODY,
        ),
        Paragraph("ALU and branch comparison", H2),
        Paragraph(
            "The ALU performs addition, subtraction, shifts, bitwise logic, and signed or unsigned set-less-than operations. The nearby branch comparator uses signed or unsigned interpretation according to the branch instruction.",
            BODY,
        ),
        Paragraph("Writeback", H2),
        Paragraph(
            f"The writeback path selects an ALU result, a completed load, or {code('PC + 4')} for a jump link. A faulting instruction never writes its destination register.",
            BODY,
        ),
        Spacer(1, 8),
        *figure(DIAGRAMS / "instruction_formats.svg", "Figure 3. Field placement in the six RV32I instruction formats.", 2.55 * inch),
        PageBreak(),
        Paragraph("Control transfers", H1),
        Paragraph(
            f"{code('JAL')} adds a J-type immediate to the current PC. {code('JALR')} adds an I-type immediate to rs1, then clears target bit 0 as required by the ISA. Bit 1 is still checked because this core requires four-byte instruction alignment.",
            BODY,
        ),
        Paragraph(
            f"A taken branch checks its target alignment. A branch that is not taken does not trap because its target is not used. A faulting {code('JAL')} or {code('JALR')} does not write its link register.",
            BODY,
        ),
        Paragraph("Loads and stores", H1),
        Paragraph(
            "Data addresses are byte addresses. Misaligned halfword and word accesses trap instead of being split into several transfers.",
            BODY,
        ),
        make_table(
            [
                ["Access", "Address bits", "Write strobe"],
                ["SB", "00, 01, 10, or 11", "0001, 0010, 0100, or 1000"],
                ["SH", "00 or 10", "0011 or 1100"],
                ["SW", "00", "1111"],
            ],
            [0.9 * inch, 2.05 * inch, 3.45 * inch],
        ),
        Spacer(1, 8),
        Paragraph(
            "Memory returns the aligned 32-bit word containing the requested bytes. The load-align block shifts the chosen byte or halfword into the low bits, then sign extends LB and LH or zero extends LBU and LHU.",
            BODY,
        ),
        Paragraph("Memory handshake", H2),
        Paragraph(
            f"The core raises {code('valid')} and keeps the address and controls stable. Memory completes the request by raising {code('ready')}. Read data and the error flag are sampled only when both signals are high. Any number of wait cycles is allowed, but the core permits only one outstanding request.",
            BODY,
        ),
        Paragraph(
            f"Because no request queue, cache, or write buffer exists, every earlier memory operation has completed when {code('FENCE')} executes. The core therefore retires {code('FENCE')} without another hardware action.",
            CALLOUT,
        ),
        PageBreak(),
        Paragraph("Traps", H1),
        Paragraph(
            "This repository does not implement the privileged architecture. A trap stops the state machine instead of redirecting the PC to a machine-mode handler.",
            BODY,
        ),
        make_table(
            [
                ["Output", "Meaning"],
                ["trap_valid_o", "Sticky high until reset"],
                ["trap_cause_o", "Standard exception number"],
                ["trap_pc_o", "Faulting instruction or failed fetch address"],
                ["trap_tval_o", "Bad instruction word or faulting address when useful"],
            ],
            [1.7 * inch, 4.7 * inch],
        ),
        Spacer(1, 10),
        Paragraph("Reset and retirement", H1),
        Paragraph(
            f"{code('rst_ni')} is asynchronous and active low. Reset clears the register file, trap record, and request state, then loads the {code('RESET_PC')} parameter.",
            BODY,
        ),
        Paragraph(
            f"{code('retire_valid_o')} pulses when an instruction completes without a trap. {code('retire_pc_o')} and {code('retire_instruction_o')} identify that instruction. These are waveform and scoreboard signals, not the full RISC-V Formal Interface.",
            BODY,
        ),
        Paragraph("Integration limits", H1),
        bullet("No machine-mode CSRs, trap vector, interrupts, or MRET."),
        bullet("No M, C, A, Zicsr, or Zifencei extensions."),
        bullet("Misaligned data is trapped rather than repaired in hardware."),
        bullet("The native memory ports need a wrapper before connection to AXI or Wishbone."),
        PageBreak(),
        Paragraph("Verification architecture", H1),
        Paragraph(
            "Verification is layered so a decoder, protocol, integration, or architectural failure has an independent observation point. The cocotb driver never reaches into register-file storage; it drives the native ports, injects deterministic wait states, and compares retirement events against the Python ISA model.",
            BODY,
        ),
        *figure(DIAGRAMS / "verification_stack.svg", "Figure 4. Source-grounded verification and waveform flow.", 3.85 * inch),
        make_table(
            [
                ["Gate", "Fresh local result", "What it establishes"],
                ["Verilator 5.048 lint", "Pass", "RTL elaborates; diagnostics reviewed"],
                ["cocotb 2.0.1 + Verilator", "2/2 pass", "Wait states, retirement scoreboard, sticky illegal trap"],
                ["Directed SystemVerilog", "3 suites pass", "10 ALU cases, full program signature, 9 trap records"],
                ["Python ISA model", "134 retired", "Independent architectural result reaches pass signature"],
            ],
            [1.45 * inch, 1.35 * inch, 3.6 * inch],
        ),
        Spacer(1, 8),
        Paragraph(
            "Waveforms are evidence for the simulated design and memory model. They do not establish FPGA timing closure, CDC safety, board wiring, or privileged-architecture compliance.",
            CALLOUT,
        ),
    ]

    doc = document(path, "RV32I core architecture")
    decorate = page_decorator("RV32I core architecture")
    doc.build(story, onFirstPage=decorate, onLaterPages=decorate)
    return path


def build_learning_guide() -> Path:
    path = OUTPUT / "learning_guide.pdf"
    signal_rows = [
        ["Signal", "What to watch"],
        ["debug_state_o", "FETCH, EXECUTE, MEMORY, then FETCH"],
        ["imem_valid_o / imem_ready_i", "Instruction request and acceptance"],
        ["dmem_valid_o / dmem_ready_i", "Load request and completion"],
        ["dmem_addr_o", "The value of x3 plus 12"],
        ["retire_valid_o", "One-cycle pulse when LW finishes"],
    ]
    story: list[Flowable] = [
        Spacer(1, 0.3 * inch),
        Paragraph("Following one load instruction", TITLE),
        Paragraph("A waveform guide for the RV32I multicycle core", SUBTITLE),
        Paragraph("Example instruction", H1),
        Paragraph("lw x5, 12(x3)", CODE),
        Paragraph(
            "The instruction adds 12 to x3, reads a 32-bit word from that address, and writes the word into x5.",
            CALLOUT,
        ),
        *figure(DIAGRAMS / "control_fsm.svg", "Figure 1. The path taken by LW is FETCH, EXECUTE, MEMORY, FETCH.", 3.15 * inch),
        Paragraph("Signals to place in the waveform", H1),
        make_table(signal_rows, [2.45 * inch, 3.95 * inch]),
        PageBreak(),
        Paragraph("1. Fetch", H1),
        Paragraph(
            f"{code('debug_state_o')} is {code('STATE_FETCH')}. {code('imem_addr_o')} equals the current PC and {code('imem_valid_o')} is high. If instruction memory is slow, the address does not change.",
            BODY,
        ),
        Paragraph(
            f"When {code('imem_ready_i')} becomes high, the core saves {code('imem_rdata_i')} in {code('instruction_q')}. The PC has not advanced yet. Keeping the PC on the current instruction makes trap reporting and PC-relative arithmetic straightforward.",
            BODY,
        ),
        Paragraph("2. Decode and address generation", H1),
        Paragraph(
            f"The state changes to {code('STATE_EXECUTE')}. Opcode {code('0000011')} selects the load group. {code('funct3=010')} selects a signed 32-bit word, which is {code('LW')}.",
            BODY,
        ),
        Paragraph(
            "The decoder requests an I-type immediate, a register write, a memory read, and the memory writeback path. The immediate generator takes instruction bits 31 through 20 and sign extends them. For this instruction its output is 12.",
            BODY,
        ),
        Paragraph(
            "The register file reads x3. The ALU adds x3 and 12. If the low two result bits are not zero, the core records a load-address-misaligned trap and never sends a memory request.",
            BODY,
        ),
        Paragraph("Expected execute values", H2),
        make_table(
            [
                ["Item", "Value"],
                ["Source register", "rs1 = x3"],
                ["Immediate", "12"],
                ["ALU operation", "x3 + 12"],
                ["Destination", "rd = x5"],
                ["Access size", "32-bit word"],
            ],
            [2.2 * inch, 4.2 * inch],
        ),
        PageBreak(),
        Paragraph("3. Memory wait", H1),
        Paragraph(
            f"For an aligned address, the state changes to {code('STATE_MEMORY')}. {code('dmem_addr_o')} is the ALU sum, {code('dmem_valid_o')} stays high, and {code('dmem_write_o')} is zero.",
            BODY,
        ),
        Paragraph(
            f"Nothing retires while {code('dmem_ready_i')} is low. The core is waiting, not repeating the instruction. When ready rises, {code('dmem_error_i')} causes a load access fault. Otherwise the 32-bit {code('dmem_rdata_i')} value is written to x5 on the clock edge.",
            BODY,
        ),
        Paragraph("Handshake timeline", H2),
        *figure(DIAGRAMS / "load_timeline.svg", "Figure 2. A load request remains stable until ready completes it.", 2.75 * inch),
        Paragraph("4. Retirement", H1),
        Paragraph(
            f"The PC increases by four, {code('retire_valid_o')} pulses, and the state returns to fetch. The register-file write and retirement pulse happen on the same completion edge.",
            BODY,
        ),
        Paragraph("Try the byte-load variation", H1),
        Paragraph("lb x5, 13(x3)", CODE),
        Paragraph(
            "The byte address is legal even when its low bits are nonzero. Memory still returns the aligned 32-bit word. The load-align block selects one byte using the low address bits and sign extends bit 7 before writing x5.",
            BODY,
        ),
        Paragraph(
            "Useful comparison: change LB to LBU and use a returned byte whose high bit is one. LB fills the upper 24 bits with ones; LBU fills them with zeros.",
            CALLOUT,
        ),
        Paragraph("Reproduce the waveform", H1),
        Paragraph(
            f"Run {code('make test-cocotb-waves PYTHON=.venv/bin/python')}. Verilator writes {code('sim/build/cocotb/dump.fst')}; open it with the checked-in {code('waves/rv32i_core.gtkw')} signal grouping. The cocotb test adds zero-to-three-cycle memory delays so stable request intervals are visible.",
            BODY,
        ),
        Paragraph(
            "GTKWave is a viewer, not a verification oracle. The pass/fail result comes from the cocotb assertions and retirement comparison; the FST trace supports diagnosis and teaching.",
            CALLOUT,
        ),
    ]

    doc = document(path, "Following one load instruction")
    decorate = page_decorator("Following one load instruction")
    doc.build(story, onFirstPage=decorate, onLaterPages=decorate)
    return path


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    generated = [build_architecture(), build_learning_guide()]
    for item in generated:
        print(item)
