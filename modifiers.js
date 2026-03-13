const fs = require('fs/promises');
const path = require('path');

const SOURCE_DATA_ROOT = process.env.SOURCE_DATA_ROOT || 'data';
const OUTPUT_DATA_ROOT =
    process.env.OUTPUT_DATA_ROOT || path.join('Mods', 'icarus_qol', 'data');

const OUTPUT_BONUS_ROWS = new Set([
  'Carbon_Fiber',
  'Epoxy',
  'Epoxy_2',
  'Composite_Paste',
  'Composite_Paste_Plat',
  'Organic_Resin',
  'Electronics',
  'Steel_Ingot',
  'Titanium_Ingot',
  'Titanium_Plate',
  'Platinum_Ingot',
  'Cobalt_Ingot',
  'Gold_Wire',
  'Copper_Wire',
  'Aluminum',
  'Glass',
  'Concrete_Mix',
  'Carbon_Paste',
  'Steel_Rebar',
  'Composites'
]);

const OUTPUT_BONUS_BY_REQUIREMENT_ROWS = new Set([
  'Stone_Basic',
  'Concrete_Basic',
  'Scoria_Basic',
  'Scoria_Brick_Basic',
  'Limestone_Basic',
  'Glass_Basic',
  'Reinforced_Glass_Basic',
  'Clay_Brick_Basic',
  'Stone_Brick_Basic',
  'Wood_Basic',
  'Thatch_Basic',
  'Interior_Wood_Basic',
  'Iron_Basic',
  'Ice_Basic',
  'Stone_Advanced',
  'Concrete_Advanced',
  'Scoria_Advanced',
  'Scoria_Brick_Advanced',
  'Limestone_Advanced',
  'Glass_Advanced',
  'Reinforced_Glass_Advanced',
  'Clay_Brick_Advanced',
  'Stone_Brick_Advanced',
  'Wood_Advanced',
  'Thatch_Advanced',
  'Interior_Wood_Advanced',
  'Iron_Advanced',
  'Ice_Advanced',
  'Stone_Diagonal',
  'Concrete_Diagonal',
  'Scoria_Diagonal',
  'Scoria_Brick_Diagonal',
  'Limestone_Diagonal',
  'Glass_Diagonal',
  'Reinforced_Glass_Diagonal',
  'Clay_Brick_Diagonal',
  'Stone_Brick_Diagonal',
  'Wood_Diagonal',
  'Thatch_Diagonal',
  'Interior_Wood_Diagonal',
  'Iron_Diagonal',
  'Ice_Diagonal',
]);

const LIQUID_TYPES = new Set([
  'Water', 'Milk', 'Biofuel', 'Refined_Oil', 'Oxygen', 'Hydrazine', 'Crude_Oil'
]);

function roundToNearestHundred(value) {
  if (value <= 0) {
    return value;
  }
  return Math.max(100, Math.round(value / 100) * 100);
}

async function transformJsonFile(inputPath, outputPath, transform) {
  let raw;
  try {
    raw = await fs.readFile(inputPath, 'utf8');
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      throw new Error(`Input JSON was not found: ${inputPath}`);
    }
    throw error;
  }
  const json = JSON.parse(raw);

  transform(json);

  await fs.mkdir(path.dirname(outputPath), {recursive: true});
  await fs.writeFile(outputPath, JSON.stringify(json, null, 2), 'utf8');
  console.log(`File written successfully: ${outputPath}`);
}

function transformProcessorRecipes(json) {
  for (const row of json.Rows || []) {
    for (const input of row.Inputs || []) {
      if (input.Count > 1) {
        input.Count = Math.ceil(input.Count / 2);
        if (input.Count > 100) {
          input.Count = 100;
        }
      }
    }

    for (const output of row.Outputs || []) {
      if (output.Count > 1) {
        output.Count = Math.ceil(output.Count * 2);
        if (output.Count > 100) {
          output.Count = 100;
        }
      }
      if (OUTPUT_BONUS_ROWS.has(row.Name)) {
        output.Count *= 2;
      }
      if (OUTPUT_BONUS_BY_REQUIREMENT_ROWS.has(row?.Requirement?.RowName)) {
        output.Count *= 2;
      }
    }

    for (const input of row.ResourceInputs || []) {
      if (input.RequiredUnits > 1) {
        const scaledUnits = Math.ceil(input.RequiredUnits / 3);
        const isRoundedLiquid =
            input.Type && LIQUID_TYPES.has(input.Type.Value);
        input.RequiredUnits =
            isRoundedLiquid ? roundToNearestHundred(scaledUnits) : scaledUnits;
      }
    }

    for (const output of row.ResourceOutputs || []) {
      if (output.RequiredUnits > 1) {
        output.RequiredUnits = Math.ceil(output.RequiredUnits * 1);
      }
    }

    if (row.RequiredMillijoules > 1) {
      row.RequiredMillijoules =
          roundToNearestHundred(Math.ceil(row.RequiredMillijoules / 4));
    }
  }
}

function transformEnergy(json) {
  for (const row of json.Rows || []) {
    if (row.FlowType === 'Produce') {
      if (row.ResourceFlowRate) {
        row.ResourceFlowRate *= 2;
      }
      if (row.ResourceFlowRate > 10000) {
        row.ResourceFlowRate = 10000;
      }
      continue;
    }

    row.ResourceFlowRate = Math.round(row.ResourceFlowRate / 200) * 100;
  }
}

function transformStackSizes(json) {
  for (const row of json.Rows || []) {
    if (row.MaxStack > 1) {
      row.MaxStack = 500;
    }
  }
}

function transformWater(json) {
  for (const row of json.Rows || []) {
    if (row.Provider && row.ResourceFlowRate) {
      row.ResourceFlowRate *= 2;
    }
    if (row.Receiver && row.ResourceFlowRate) {
      row.ResourceFlowRate = Math.ceil(row.ResourceFlowRate / 4);
    }
  }
}

async function main() {
  const source = (relativePath) => path.join(SOURCE_DATA_ROOT, relativePath);
  const output = (relativePath) => path.join(OUTPUT_DATA_ROOT, relativePath);

  const jobs = [
    {
      inputPath: source(path.join('Crafting', 'D_ProcessorRecipes.json')),
      outputPath: output(path.join('Crafting', 'D_ProcessorRecipes.json')),
      transform: transformProcessorRecipes,
    },
    {
      inputPath: source(path.join('Traits', 'D_Energy.json')),
      outputPath: output(path.join('Traits', 'D_Energy.json')),
      transform: transformEnergy,
    },
    {
      inputPath: source(path.join('Traits', 'D_Water.json')),
      outputPath: output(path.join('Traits', 'D_Water.json')),
      transform: transformWater,
    },
    {
      inputPath: source(path.join('Traits', 'D_Itemable.json')),
      outputPath: output(path.join('Traits', 'D_Itemable.json')),
      transform: transformStackSizes,
    },
  ];

  for (const job of jobs) {
    await transformJsonFile(job.inputPath, job.outputPath, job.transform);
  }
}

main().catch((error) => {
  console.error('Modifier run failed:', error);
  process.exitCode = 1;
});
