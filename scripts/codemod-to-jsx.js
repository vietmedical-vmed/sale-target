/**
 * jscodeshift codemod: convert React.createElement / h() to JSX
 *
 * Step 1: Find `const h = React.createElement` bindings, replace all `h(...)`
 *         in their scope with `React.createElement(...)`, remove the binding.
 * Step 2: Convert `React.createElement(type, props, ...children)` to JSX.
 */
export default function transformer(fileInfo, api) {
  const j = api.jscodeshift;
  let root = j(fileInfo.source);

  // ── Step 1: normalize h → React.createElement ──
  root
    .find(j.VariableDeclarator, {
      id: { name: 'h' },
      init: {
        type: 'MemberExpression',
        object: { name: 'React' },
        property: { name: 'createElement' },
      },
    })
    .forEach(path => {
      const scope = path.scope;
      j(scope.path)
        .find(j.CallExpression, { callee: { name: 'h' } })
        .forEach(callPath => {
          const binding = callPath.scope.lookup('h');
          if (binding === scope) {
            callPath.node.callee = j.memberExpression(
              j.identifier('React'),
              j.identifier('createElement')
            );
          }
        });
      // remove `const h = React.createElement;`
      const decl = path.parent;
      if (
        decl.node.type === 'VariableDeclaration' &&
        decl.node.declarations.length === 1
      ) {
        j(decl).remove();
      } else {
        j(path).remove();
      }
    });

  // ── Step 2: createElement → JSX ──
  function isCreateElement(node) {
    return (
      node.type === 'CallExpression' &&
      node.callee.type === 'MemberExpression' &&
      node.callee.object.name === 'React' &&
      node.callee.property.name === 'createElement'
    );
  }

  function toJSX(node) {
    if (!isCreateElement(node)) return node;

    const [type, props, ...children] = node.arguments;
    if (!type) return node;

    // Determine element name
    let jsxName;
    if (type.type === 'StringLiteral' || type.type === 'Literal') {
      jsxName = j.jsxIdentifier(type.value);
    } else if (type.type === 'Identifier') {
      jsxName = j.jsxIdentifier(type.name);
    } else if (
      type.type === 'MemberExpression' &&
      type.object.type === 'Identifier' &&
      type.property.type === 'Identifier'
    ) {
      jsxName = j.jsxMemberExpression(
        j.jsxIdentifier(type.object.name),
        j.jsxIdentifier(type.property.name)
      );
    } else {
      return node;
    }

    // Convert props to JSX attributes
    const attrs = [];
    if (props && props.type !== 'NullLiteral' && !(props.type === 'Literal' && props.value === null)) {
      if (props.type === 'ObjectExpression') {
        for (const prop of props.properties) {
          if (prop.type === 'SpreadElement' || prop.type === 'SpreadProperty') {
            attrs.push(j.jsxSpreadAttribute(prop.argument));
          } else if (prop.key) {
            const keyName =
              prop.key.type === 'Identifier'
                ? prop.key.name
                : prop.key.type === 'StringLiteral' || prop.key.type === 'Literal'
                  ? prop.key.value
                  : null;
            if (keyName === null) {
              // computed key — can't convert to JSX
              attrs.push(j.jsxSpreadAttribute(
                j.objectExpression([prop])
              ));
              continue;
            }
            const attrName = j.jsxIdentifier(keyName);
            let attrValue;
            const val = prop.value;
            // String literal → JSX string
            if (
              (val.type === 'StringLiteral' || (val.type === 'Literal' && typeof val.value === 'string')) &&
              !val.value.includes('{') &&
              !val.value.includes('}')
            ) {
              attrValue = j.literal(val.value);
            } else if (val.type === 'BooleanLiteral' || (val.type === 'Literal' && val.value === true)) {
              attrValue = null; // boolean true → just the attribute name
            } else {
              attrValue = j.jsxExpressionContainer(val);
            }
            attrs.push(j.jsxAttribute(attrName, attrValue));
          }
        }
      } else {
        // props is an expression (e.g. variable) → spread it
        attrs.push(j.jsxSpreadAttribute(props));
      }
    }

    // If any child is a SpreadElement, can't convert to JSX cleanly
    if (children.some(c => c && c.type === 'SpreadElement')) {
      return node;
    }

    // Convert children
    const jsxChildren = [];
    for (const child of children) {
      if (!child) continue;
      const converted = toJSX(child);
      if (
        converted.type === 'StringLiteral' ||
        (converted.type === 'Literal' && typeof converted.value === 'string')
      ) {
        jsxChildren.push(j.jsxText(converted.value));
      } else if (converted.type === 'JSXElement' || converted.type === 'JSXFragment') {
        jsxChildren.push(converted);
      } else {
        jsxChildren.push(j.jsxExpressionContainer(converted));
      }
    }

    const openingEl = j.jsxOpeningElement(jsxName, attrs, jsxChildren.length === 0);
    const closingEl = jsxChildren.length === 0 ? null : j.jsxClosingElement(jsxName);
    return j.jsxElement(openingEl, closingEl, jsxChildren, jsxChildren.length === 0);
  }

  // Walk bottom-up: convert innermost createElement calls first
  let changed = true;
  let iterations = 0;
  while (changed && iterations < 20) {
    changed = false;
    iterations++;
    root.find(j.CallExpression).forEach(path => {
      if (isCreateElement(path.node)) {
        const jsx = toJSX(path.node);
        if (jsx !== path.node) {
          // Remove /*#__PURE__*/ comment if present
          if (path.node.leadingComments) {
            path.node.leadingComments = path.node.leadingComments.filter(
              c => !c.value.includes('__PURE__')
            );
          }
          j(path).replaceWith(jsx);
          changed = true;
        }
      }
    });
  }

  return root.toSource({ quote: 'single' });
}
